#!/usr/bin/env bash
#
# HBv4 local-NVMe setup workflow
# --------------------------------
# This helper is the only code allowed to turn the two ephemeral HBv4 NVMe
# devices into runner scratch space.  Its entry point first discovers and
# validates every candidate without changing block-device state, then either:
#
#   * validates and mounts the one already-complete GEOS RAID-0 array; or
#   * creates a new RAID-0 array, formats it as XFS, and mounts it.
#
# Every exclusion is deliberately fail-closed.  Discovery enumerates kernel
# NVMe namespaces, reads each controller model with `nvme id-ctrl`, and queries
# type and byte size independently so whitespace in an Azure model string can
# never change the field layout.  A disk is not considered disposable merely
# because its model matches: it must also be the expected size, be a whole
# unused device, have no signatures or RAID metadata, and be outside all
# protected OS/resource-disk ancestry.  Future changes must preserve the
# "validate everything before the first mutation" boundary.

set -euo pipefail

readonly EXPECTED_MODEL="Microsoft NVMe Direct Disk"
readonly EXPECTED_SIZE_MIB=1831054
readonly EXPECTED_SIZE_BYTES=$(( EXPECTED_SIZE_MIB * 1024 * 1024 ))
readonly SIZE_TOLERANCE_BYTES=$(( EXPECTED_SIZE_BYTES / 100 ))
readonly EXPECTED_LABEL="hbv4-local"

DRY_RUN=false
case "${1:-}" in
  "")
    ;;
  --dry-run)
    DRY_RUN=true
    ;;
  *)
    echo "Usage: $0 [--dry-run]" >&2
    exit 2
    ;;
esac

# Tests exercise destructive-looking branches against regular files and command
# shims.  Production ignores all path overrides unless the explicit test-mode
# sentinel is present, so an accidentally inherited individual variable cannot
# redirect storage setup away from the real Azure devices.
if [[ "${GEOS_HBV4_TEST_MODE:-0}" == "1" ]]; then
  DEV_ROOT="${GEOS_HBV4_TEST_DEV_ROOT:-/dev}"
  BY_ID_DIR="${GEOS_HBV4_TEST_BY_ID_DIR:-/dev/disk/by-id}"
  AZURE_DISK_DIR="${GEOS_HBV4_TEST_AZURE_DISK_DIR:-/dev/disk/azure}"
  AZURE_LOCAL_BY_SERIAL_DIR="${GEOS_HBV4_TEST_AZURE_LOCAL_BY_SERIAL_DIR:-/dev/disk/azure/local/by-serial}"
  SYS_CLASS_BLOCK_DIR="${GEOS_HBV4_TEST_SYS_CLASS_BLOCK_DIR:-/sys/class/block}"
  PROC_SWAPS="${GEOS_HBV4_TEST_PROC_SWAPS:-/proc/swaps}"
  MD_DEVICE="${GEOS_HBV4_TEST_MD_DEVICE:-/dev/md/hbv4-local}"
  MOUNT_POINT="${GEOS_HBV4_TEST_MOUNT_POINT:-/mnt/hbv4-local}"
  LOCK_FILE="${GEOS_HBV4_TEST_LOCK_FILE:-/run/lock/geos-hbv4-local-nvme.lock}"
else
  DEV_ROOT="/dev"
  BY_ID_DIR="/dev/disk/by-id"
  AZURE_DISK_DIR="/dev/disk/azure"
  AZURE_LOCAL_BY_SERIAL_DIR="/dev/disk/azure/local/by-serial"
  SYS_CLASS_BLOCK_DIR="/sys/class/block"
  PROC_SWAPS="/proc/swaps"
  MD_DEVICE="/dev/md/hbv4-local"
  MOUNT_POINT="/mnt/hbv4-local"
  LOCK_FILE="/run/lock/geos-hbv4-local-nvme.lock"
fi
readonly DEV_ROOT BY_ID_DIR AZURE_DISK_DIR AZURE_LOCAL_BY_SERIAL_DIR
readonly SYS_CLASS_BLOCK_DIR PROC_SWAPS MD_DEVICE MOUNT_POINT LOCK_FILE

die()
{
  echo "ERROR: $*" >&2
  exit 1
}

[[ "$(id -u)" == "0" ]] || die "HBv4 local-NVMe setup must run as root"

for command_name in blkid find findmnt flock grep lsblk mdadm mkfs.xfs mount mountpoint nvme readlink xfs_info; do
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "required command is unavailable: ${command_name}"
done

# The nonblocking process lock prevents two bootstrap invocations from both
# passing discovery before either creates the array.  Opening the lock file is
# the only setup-side effect that occurs before block-device validation.
mkdir -p "$(dirname "${LOCK_FILE}")"
exec {LOCK_FD}>"${LOCK_FILE}"
flock -n "${LOCK_FD}" || die "another HBv4 local-NVMe setup process holds ${LOCK_FILE}"

run_mutation()
{
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

canonical_path()
{
  readlink -f -- "$1"
}

# Normalize the fixed-width padding used by `nvme id-ctrl` without interpreting
# any controller-provided characters.  The returned model remains the identity
# string used by the exact Azure disk-model allowlist below.
trim_whitespace()
{
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

# Read the NVMe Identify Controller `mn` field from one namespace.  Microsoft
# documents this controller query for distinguishing Azure NVMe devices.  A
# missing field or failed query is a rejected observation rather than an
# accepted disk; the caller reports that reason before enforcing cardinality.
nvme_controller_model()
{
  local raw_device="$1"
  local identify_output
  local identify_line
  local model

  identify_output="$(nvme id-ctrl "${raw_device}" 2>/dev/null)" || return 1
  while IFS= read -r identify_line; do
    if [[ "${identify_line}" =~ ^[[:space:]]*mn[[:space:]]*:[[:space:]]*(.*)$ ]]; then
      model="$(trim_whitespace "${BASH_REMATCH[1]}")"
      [[ -n "${model}" ]] || return 1
      printf '%s\n' "${model}"
      return 0
    fi
  done <<<"${identify_output}"

  return 1
}

# Select a deterministic stable path when udev exposes one.  The kernel name is
# retained as the identity used for topology/sysfs checks, while the stable link
# is used as the mdadm member argument so enumeration order cannot swap members.
stable_member_path()
{
  local raw_device="$1"
  local raw_canonical
  local stable_dir
  local link
  local link_canonical
  local -a matches=()

  raw_canonical="$(canonical_path "${raw_device}")" ||
    die "cannot resolve candidate device ${raw_device}"

  # Azure's local-NVMe serial links describe the intended platform identity and
  # therefore outrank generic by-id aliases.  Each directory is sorted
  # independently so adding a lower-priority alias cannot reorder members.
  for stable_dir in "${AZURE_LOCAL_BY_SERIAL_DIR}" "${BY_ID_DIR}"; do
    matches=()
    [[ -d "${stable_dir}" ]] || continue
    while IFS= read -r link; do
      [[ "${link}" =~ -part[0-9]+$ ]] && continue
      link_canonical="$(canonical_path "${link}")" || continue
      [[ "${link_canonical}" == "${raw_canonical}" ]] && matches+=("${link}")
    done < <(find "${stable_dir}" -maxdepth 1 -type l -print 2>/dev/null | LC_ALL=C sort)
    if (( ${#matches[@]} > 0 )); then
      printf '%s\n' "${matches[0]}"
      return
    fi
  done

  printf '%s\n' "${raw_device}"
}

# Return success when candidate_device belongs to the same lsblk ancestry as a
# protected mount source.  This catches partitions, dm-crypt/LVM layers, and
# other indirections rather than relying on fragile kernel-name conventions.
device_is_in_source_chain()
{
  local candidate_device="$1"
  local source_device="$2"
  local chain_device
  local candidate_canonical
  local chain_output

  candidate_canonical="$(canonical_path "${candidate_device}")" ||
    die "cannot resolve protected-chain candidate ${candidate_device}"
  chain_output="$(lsblk -srnpo NAME -- "${source_device}")" ||
    die "cannot inspect protected block ancestry for ${source_device}"

  while IFS= read -r chain_device; do
    [[ -n "${chain_device}" ]] || continue
    if [[ "$(canonical_path "${chain_device}" 2>/dev/null || true)" == "${candidate_canonical}" ]]; then
      return 0
    fi
  done <<<"${chain_output}"
  return 1
}

# Collect exact protected mountpoints rather than using findmnt --target, whose
# parent-filesystem fallback would incorrectly classify an ordinary /mnt
# directory as a separate Azure resource disk.
declare -a protected_sources=()
for protected_mount in / /boot /boot/efi /mnt /mnt/resource /mnt/resource_nvme; do
  protected_source=""
  if protected_source="$(findmnt -rn -o SOURCE --mountpoint "${protected_mount}")"; then
    protected_source="${protected_source%%\[*}"
    [[ -n "${protected_source}" ]] &&
      protected_sources+=("${protected_source}")
  else
    findmnt_status=$?
    if [[ "${protected_mount}" == "/" || ${findmnt_status} -gt 1 ]]; then
      die "cannot determine protected mount source for ${protected_mount}"
    fi
  fi
done

# WALinuxAgent exposes OS and resource-disk identities even when those devices
# are not mounted.  Protect their full ancestry explicitly so a transient mount
# failure can never turn an Azure-owned device into a scratch candidate.
for azure_owned_link in "${AZURE_DISK_DIR}/os" "${AZURE_DISK_DIR}/resource"; do
  if [[ -e "${azure_owned_link}" ]]; then
    protected_sources+=("${azure_owned_link}")
  fi
done

# Enumerate namespace names first, then identify type, byte size, and controller
# model through independent commands.  The prior combined lsblk record did not
# classify either live HBv4 disk, and its whitespace-delimited MODEL field made
# the mismatch ambiguous.  Reading the controller identity per device removes
# that field-layout dependency.  The diagnostics below make every identity
# rejection visible before the exact-two cardinality guard stops setup.
declare -a discovered_records=()
discovery_output="$(lsblk -dnpo NAME)" ||
  die "cannot enumerate whole block-device names"
while IFS= read -r listed_device; do
  listed_device="$(trim_whitespace "${listed_device}")"
  [[ -n "${listed_device}" ]] || continue
  device_name="$(basename "${listed_device}")"
  [[ "${device_name}" =~ ^nvme[0-9]+n[0-9]+$ ]] || continue

  # The enumerated production path is rooted at /dev.  Rebuilding it below the
  # guarded DEV_ROOT keeps fixtures incapable of addressing host block devices
  # while preserving the same kernel basename used by sysfs and topology checks.
  raw_device="${DEV_ROOT}/${device_name}"
  [[ -b "${raw_device}" || ( "${GEOS_HBV4_TEST_MODE:-0}" == "1" && -e "${raw_device}" ) ]] ||
    die "enumerated NVMe namespace does not exist as a device: ${raw_device}"

  device_type="$(lsblk -dno TYPE -- "${listed_device}")" ||
    die "cannot inspect block-device type for ${raw_device}"
  device_type="$(trim_whitespace "${device_type}")"
  device_size="$(lsblk -dnbo SIZE -- "${listed_device}")" ||
    die "cannot inspect byte size for ${raw_device}"
  device_size="$(trim_whitespace "${device_size}")"
  [[ "${device_size}" =~ ^[0-9]+$ ]] || {
    printf 'HBv4 NVMe observed: device=%s type=%q model=%q size_bytes=%q decision=rejected reason=%q\n' \
      "${raw_device}" "${device_type}" "<not-read>" "${device_size}" \
      "byte-size query returned a nonnumeric value" >&2
    die "cannot safely classify ${raw_device} with a nonnumeric byte size"
  }

  if ! device_model="$(nvme_controller_model "${raw_device}")"; then
    printf 'HBv4 NVMe observed: device=%s type=%q model=%q size_bytes=%s decision=rejected reason=%q\n' \
      "${raw_device}" "${device_type}" "<unavailable>" "${device_size}" \
      "nvme id-ctrl failed or returned no model field" >&2
    continue
  fi

  rejection_reason=""
  if [[ "${device_type}" != "disk" ]]; then
    rejection_reason="lsblk type is not a whole disk"
  elif [[ "${device_model}" != "${EXPECTED_MODEL}" ]]; then
    rejection_reason="controller model does not match the HBv4 ephemeral-disk allowlist"
  else
    size_delta=$(( device_size - EXPECTED_SIZE_BYTES ))
    (( size_delta < 0 )) && size_delta=$(( -size_delta ))
    if (( size_delta > SIZE_TOLERANCE_BYTES )); then
      rejection_reason="byte size is outside the one-percent HBv4 tolerance"
    fi
  fi

  if [[ -n "${rejection_reason}" ]]; then
    printf 'HBv4 NVMe observed: device=%s type=%q model=%q size_bytes=%s decision=rejected reason=%q\n' \
      "${raw_device}" "${device_type}" "${device_model}" "${device_size}" \
      "${rejection_reason}" >&2
    continue
  fi

  stable_device="$(stable_member_path "${raw_device}")"
  discovered_records+=("${stable_device}|${raw_device}|${device_model}|${device_size}")
  printf 'HBv4 NVMe observed: device=%s type=%q model=%q size_bytes=%s decision=accepted\n' \
    "${raw_device}" "${device_type}" "${device_model}" "${device_size}"
done <<<"${discovery_output}"

(( ${#discovered_records[@]} == 2 )) ||
  die "expected exactly two validated HBv4 ephemeral NVMe devices; found ${#discovered_records[@]}"

mapfile -t discovered_records < <(printf '%s\n' "${discovered_records[@]}" | LC_ALL=C sort)

declare -a member_devices=()
declare -a raw_devices=()
for record in "${discovered_records[@]}"; do
  IFS='|' read -r member_device raw_device device_model device_size <<<"${record}"
  member_devices+=("${member_device}")
  raw_devices+=("${raw_device}")
  printf 'HBv4 NVMe candidate: device=%s stable=%s model=%q size_bytes=%s\n' \
    "${raw_device}" "${member_device}" "${device_model}" "${device_size}"
done

[[ "$(canonical_path "${raw_devices[0]}")" != "$(canonical_path "${raw_devices[1]}")" ]] ||
  die "the two candidate records resolve to the same block device"

array_exists=false
[[ -e "${MD_DEVICE}" ]] && array_exists=true

# Validate the destination namespace before any mdadm or mkfs mutation. A lost
# mount can leave files in the underlying OS-disk directory, while a symlink or
# unrelated mount can redirect the eventual mount over state this helper does
# not own. An already-mounted destination is meaningful only when the expected
# array also exists; its exact source/filesystem/options are checked below.
[[ ! -L "${MOUNT_POINT}" ]] ||
  die "mount point ${MOUNT_POINT} is a symbolic link"
[[ ! -e "${MOUNT_POINT}" || -d "${MOUNT_POINT}" ]] ||
  die "mount point ${MOUNT_POINT} exists but is not a directory"
if mountpoint -q "${MOUNT_POINT}"; then
  [[ "${array_exists}" == "true" ]] ||
    die "${MOUNT_POINT} is already mounted while ${MD_DEVICE} is absent"
else
  mountpoint_status=$?
  [[ ${mountpoint_status} -eq 1 ]] ||
    die "cannot determine whether ${MOUNT_POINT} is mounted"
  if [[ -d "${MOUNT_POINT}" ]] &&
     [[ -n "$(find "${MOUNT_POINT}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    die "unmounted destination ${MOUNT_POINT} is not empty"
  fi
fi

reject_candidate()
{
  die "candidate ${1} is not pristine ephemeral scratch: ${2}"
}

# Complete every destructive precondition for both members before deciding
# whether an array should be created.  A failure on the second member therefore
# cannot leave a half-created array from an already-accepted first member.
for raw_device in "${raw_devices[@]}"; do
  topology_output="$(lsblk -nrpo NAME,TYPE,MOUNTPOINT -- "${raw_device}")" ||
    die "cannot inspect topology for ${raw_device}"
  [[ -n "${topology_output}" ]] || die "lsblk returned no topology for ${raw_device}"
  mapfile -t topology_lines <<<"${topology_output}"
  read -r topology_name topology_type topology_mount <<<"${topology_lines[0]}"
  [[ "$(canonical_path "${topology_name}")" == "$(canonical_path "${raw_device}")" ]] ||
    reject_candidate "${raw_device}" "lsblk topology begins with a different device"
  [[ "${topology_type}" == "disk" ]] ||
    reject_candidate "${raw_device}" "candidate is not a whole disk"
  [[ -z "${topology_mount:-}" ]] ||
    reject_candidate "${raw_device}" "whole device is mounted at ${topology_mount}"

  if [[ "${array_exists}" == "false" ]]; then
    (( ${#topology_lines[@]} == 1 )) ||
      reject_candidate "${raw_device}" "device has partitions or descendants"
  else
    # An assembled expected array appears as the sole lsblk descendant of each
    # member.  Permit only that exact descendant here; its geometry, members,
    # filesystem, and mount are independently validated below.
    (( ${#topology_lines[@]} == 2 )) ||
      reject_candidate "${raw_device}" "existing-array member has unexpected descendants"
    read -r descendant_name descendant_type descendant_mount <<<"${topology_lines[1]}"
    [[ "$(canonical_path "${descendant_name}")" == "$(canonical_path "${MD_DEVICE}")" ]] ||
      reject_candidate "${raw_device}" "descendant is not the expected GEOS array"
    [[ "${descendant_type}" == "raid0" ]] ||
      reject_candidate "${raw_device}" "expected array descendant is not RAID-0"
    [[ -z "${descendant_mount:-}" || "${descendant_mount}" == "${MOUNT_POINT}" ]] ||
      reject_candidate "${raw_device}" "array descendant is mounted at an unexpected path"
  fi

  for protected_source in "${protected_sources[@]}"; do
    if device_is_in_source_chain "${raw_device}" "${protected_source}"; then
      reject_candidate "${raw_device}" \
        "device overlaps protected OS, boot, EFI, or Azure resource storage"
    fi
  done

  device_base="$(basename "$(canonical_path "${raw_device}")")"
  holders_dir="${SYS_CLASS_BLOCK_DIR}/${device_base}/holders"
  if [[ "${array_exists}" == "false" && -d "${holders_dir}" ]] &&
     compgen -G "${holders_dir}/*" >/dev/null; then
    reject_candidate "${raw_device}" "device has block holders"
  fi

  if [[ -r "${PROC_SWAPS}" ]]; then
    while read -r swap_device _; do
      [[ "${swap_device}" == "Filename" || -z "${swap_device}" ]] && continue
      if [[ "$(canonical_path "${swap_device}" 2>/dev/null || true)" == \
            "$(canonical_path "${raw_device}")" ]]; then
        reject_candidate "${raw_device}" "device is active swap"
      fi
    done < "${PROC_SWAPS}"
  else
    die "cannot inspect active swap devices at ${PROC_SWAPS}"
  fi
done

if [[ "${array_exists}" == "true" ]]; then
  # An existing array is accepted only if mdadm and sysfs independently agree
  # on its geometry and exact active members. RAID-0 has no redundant members,
  # so Linux does not expose the redundancy-only md/degraded attribute for this
  # level. The declared two-device geometry plus the exact sysfs slave set is
  # therefore the fail-closed completeness contract. Member signatures are
  # expected here and are validated through the array rather than rejected as
  # foreign metadata.
  md_level=""
  md_devices=""
  while IFS='=' read -r detail_key detail_value; do
    case "${detail_key}" in
      MD_LEVEL) md_level="${detail_value}" ;;
      MD_DEVICES) md_devices="${detail_value}" ;;
    esac
  done < <(mdadm --detail --export "${MD_DEVICE}")
  [[ "${md_level}" == "raid0" && "${md_devices}" == "2" ]] ||
    die "existing ${MD_DEVICE} does not declare a two-device RAID-0 geometry"

  md_base="$(basename "$(canonical_path "${MD_DEVICE}")")"
  md_sysfs_dir="${SYS_CLASS_BLOCK_DIR}/${md_base}/md"
  [[ -r "${md_sysfs_dir}/level" &&
     -r "${md_sysfs_dir}/raid_disks" ]] ||
    die "existing array has no readable sysfs RAID geometry"
  read -r sysfs_md_level < "${md_sysfs_dir}/level"
  read -r sysfs_raid_disks < "${md_sysfs_dir}/raid_disks"
  [[ "${sysfs_md_level}" == "raid0" &&
     "${sysfs_raid_disks}" == "2" ]] ||
    die "existing ${MD_DEVICE} does not declare two-device RAID-0 geometry in sysfs"

  slaves_dir="${SYS_CLASS_BLOCK_DIR}/${md_base}/slaves"
  [[ -d "${slaves_dir}" ]] || die "existing array has no readable sysfs slave set"
  mapfile -t actual_members < <(
    for slave_path in "${slaves_dir}"/*; do
      [[ -e "${slave_path}" ]] && basename "${slave_path}"
    done | LC_ALL=C sort
  )
  mapfile -t expected_members < <(
    for raw_device in "${raw_devices[@]}"; do
      basename "$(canonical_path "${raw_device}")"
    done | LC_ALL=C sort
  )
  [[ "${actual_members[*]}" == "${expected_members[*]}" ]] ||
    die "existing array members do not exactly match the two validated HBv4 devices"

  # Each member must be held only by this array.  This closes the gap left by
  # allowing the expected md descendant during generic topology validation.
  for raw_device in "${raw_devices[@]}"; do
    device_base="$(basename "$(canonical_path "${raw_device}")")"
    member_holders_dir="${SYS_CLASS_BLOCK_DIR}/${device_base}/holders"
    [[ -d "${member_holders_dir}" ]] ||
      die "existing array member ${raw_device} has no readable holder set"
    mapfile -t actual_holders < <(
      for holder_path in "${member_holders_dir}"/*; do
        [[ -e "${holder_path}" ]] && basename "${holder_path}"
      done | LC_ALL=C sort
    )
    [[ "${actual_holders[*]}" == "${md_base}" ]] ||
      die "existing array member ${raw_device} has an unexpected holder set"
  done

  [[ "$(blkid -s TYPE -o value "${MD_DEVICE}")" == "xfs" ]] ||
    die "existing array filesystem is not XFS"
  [[ "$(blkid -s LABEL -o value "${MD_DEVICE}")" == "${EXPECTED_LABEL}" ]] ||
    die "existing array filesystem label is not ${EXPECTED_LABEL}"
  xfs_geometry="$(xfs_info "${MD_DEVICE}")" ||
    die "cannot inspect existing XFS geometry"
  grep -Eq '(^|[[:space:]])ftype=1([[:space:]]|$)' <<<"${xfs_geometry}" ||
    die "existing XFS filesystem does not have directory ftype=1"
else
  # No array may be created if either member already carries any filesystem or
  # RAID signature.  These probes intentionally distinguish "nothing found"
  # from an operational inspection error.
  for raw_device in "${raw_devices[@]}"; do
    if blkid -p "${raw_device}" >/dev/null 2>&1; then
      reject_candidate "${raw_device}" "device contains a filesystem or partition signature"
    else
      probe_status=$?
      [[ ${probe_status} -eq 2 ]] ||
        reject_candidate "${raw_device}" "filesystem-signature inspection failed"
    fi

    if mdadm --examine "${raw_device}" >/dev/null 2>&1; then
      reject_candidate "${raw_device}" "device contains stale or foreign RAID metadata"
    else
      examine_status=$?
      [[ ${examine_status} -eq 1 ]] ||
        reject_candidate "${raw_device}" "RAID-metadata inspection failed"
    fi
  done

  run_mutation mkdir -p "$(dirname "${MD_DEVICE}")"
  run_mutation mdadm --create "${MD_DEVICE}" --run --level=0 --raid-devices=2 \
    --metadata=1.2 "${member_devices[@]}"
  run_mutation mkfs.xfs -f -L "${EXPECTED_LABEL}" -n ftype=1 "${MD_DEVICE}"
fi

if mountpoint -q "${MOUNT_POINT}"; then
  mounted_record="$(findmnt -rn -o SOURCE,FSTYPE,OPTIONS --mountpoint "${MOUNT_POINT}")" ||
    die "cannot inspect existing mount at ${MOUNT_POINT}"
  read -r mounted_source mounted_type mounted_options <<<"${mounted_record}"
  [[ "$(canonical_path "${mounted_source}")" == "$(canonical_path "${MD_DEVICE}")" ]] ||
    die "${MOUNT_POINT} is mounted from an unexpected source"
  [[ "${mounted_type}" == "xfs" ]] || die "${MOUNT_POINT} is not mounted as XFS"
  [[ ",${mounted_options}," == *,noatime,* ]] ||
    die "${MOUNT_POINT} is missing the required noatime option"
else
  mountpoint_status=$?
  [[ ${mountpoint_status} -eq 1 ]] ||
    die "cannot determine whether ${MOUNT_POINT} is mounted"
  run_mutation mkdir -p "${MOUNT_POINT}"
  run_mutation mount -t xfs -o noatime "LABEL=${EXPECTED_LABEL}" "${MOUNT_POINT}"
fi

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "HBv4 local-NVMe dry run completed without changing block-device state."
else
  echo "HBv4 local-NVMe RAID-0 is mounted at ${MOUNT_POINT}."
fi
