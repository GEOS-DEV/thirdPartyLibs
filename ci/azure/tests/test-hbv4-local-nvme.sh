#!/usr/bin/env bash
# shellcheck disable=SC2016
#
# Mocked HBv4 local-NVMe safety fixtures
# --------------------------------------
# Each fixture supplies regular files plus PATH-injected command shims to the
# production helper.  Discovery deliberately models the Azure live shape:
# lsblk enumerates namespace paths while `nvme id-ctrl` returns the padded
# multiword controller model independently.  Negative cases model one malformed
# or ambiguous storage state at a time and assert that the validation boundary
# prevents mdadm create, mkfs, and mount.  No fixture can address a host block
# device.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
HELPER="${REPO_ROOT}/ci/azure/scripts/setup-hbv4-local-nvme.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

EXPECTED_BYTES=$(( 1831054 * 1024 * 1024 ))
failures=0

fail()
{
  echo "FAIL: $*" >&2
  failures=$(( failures + 1 ))
}

make_mock()
{
  local case_dir="$1"
  local command_name="$2"
  shift 2
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    printf '%s\n' "$@"
  } > "${case_dir}/bin/${command_name}"
  chmod +x "${case_dir}/bin/${command_name}"
}

new_case()
{
  local name="$1"
  CASE_DIR="${TEST_ROOT}/${name}"
  mkdir -p \
    "${CASE_DIR}/bin" \
    "${CASE_DIR}/dev/disk/by-id" \
    "${CASE_DIR}/dev/disk/azure/local/by-serial" \
    "${CASE_DIR}/dev/md" \
    "${CASE_DIR}/sys/class/block" \
    "${CASE_DIR}/mount" \
    "${CASE_DIR}/run"
  : > "${CASE_DIR}/mutations.log"
  printf 'Filename Type Size Used Priority\n' > "${CASE_DIR}/swaps"
  printf '%s\n' "/dev/osdisk" > "${CASE_DIR}/protected-root"
  printf '%s\n' "/dev/osdisk" > "${CASE_DIR}/chain-osdisk"
  printf '%s\n' "/dev/nvme0n1" "/dev/nvme1n1" \
    > "${CASE_DIR}/discovery"
  for device in nvme0n1 nvme1n1; do
    : > "${CASE_DIR}/dev/${device}"
    mkdir -p "${CASE_DIR}/sys/class/block/${device}/holders"
    printf 'disk\n' > "${CASE_DIR}/type-${device}"
    printf '%s\n' "${EXPECTED_BYTES}" > "${CASE_DIR}/size-${device}"
    printf 'Microsoft NVMe Direct Disk\n' > "${CASE_DIR}/model-${device}"
    printf '%s disk\n' "${CASE_DIR}/dev/${device}" > "${CASE_DIR}/topology-${device}"
    ln -s "../../${device}" "${CASE_DIR}/dev/disk/by-id/azure-${device}"
    ln -s "../../../../${device}" \
      "${CASE_DIR}/dev/disk/azure/local/by-serial/serial-${device}"
  done

  make_mock "${CASE_DIR}" id \
    'if [[ "${1:-}" == "-u" ]]; then echo "${MOCK_UID:-0}"; else /usr/bin/id "$@"; fi'
  make_mock "${CASE_DIR}" flock \
    '[[ "${MOCK_FORCE_LOCKED:-0}" != 1 ]]'
  make_mock "${CASE_DIR}" lsblk \
    'args=" $* "' \
    'if [[ "${args}" == *" -dnpo NAME "* ]]; then cat "${MOCK_CASE_DIR}/discovery"; exit 0; fi' \
    'if [[ "${args}" == *" -srnpo "* ]]; then' \
    '  source_device="${!#}"; chain_file="${MOCK_CASE_DIR}/chain-$(basename "${source_device}")"' \
    '  [[ -f "${chain_file}" ]] || exit 1' \
    '  cat "${chain_file}"; exit 0' \
    'fi' \
    'device="${!#}"; device_base="$(basename "${device}")"' \
    'if [[ "${args}" == *" -dno TYPE "* ]]; then cat "${MOCK_CASE_DIR}/type-${device_base}"; exit 0; fi' \
    'if [[ "${args}" == *" -dnbo SIZE "* ]]; then cat "${MOCK_CASE_DIR}/size-${device_base}"; exit 0; fi' \
    'device="${!#}"; cat "${MOCK_CASE_DIR}/topology-$(basename "${device}")"'
  make_mock "${CASE_DIR}" nvme \
    '[[ "${1:-}" == "id-ctrl" ]] || exit 99' \
    'device_base="$(basename "${2}")"' \
    '[[ ",${MOCK_NVME_ID_FAILURES:-}," != *",${device_base},"* ]] || exit 1' \
    'printf "vid       : 0x1414\nmn        : %s   \nfr        : 1.0\n" "$(<"${MOCK_CASE_DIR}/model-${device_base}")"'
  make_mock "${CASE_DIR}" findmnt \
    'args=" $* "' \
    'mount_arg="${!#}"' \
    'if [[ "${args}" == *" SOURCE,FSTYPE,OPTIONS "* ]]; then' \
    '  [[ "${MOCK_MOUNTED:-0}" == 1 ]] || exit 1' \
    '  printf "%s xfs %s\n" "${MOCK_MD_DEVICE}" "${MOCK_MOUNT_OPTIONS:-rw,noatime}"' \
    '  exit 0' \
    'fi' \
    'if [[ "${mount_arg}" == "/" ]]; then cat "${MOCK_CASE_DIR}/protected-root"; exit 0; fi' \
    'if [[ -f "${MOCK_CASE_DIR}/protected-$(basename "${mount_arg}")" ]]; then' \
    '  cat "${MOCK_CASE_DIR}/protected-$(basename "${mount_arg}")"; exit 0' \
    'fi' \
    'exit 1'
  make_mock "${CASE_DIR}" blkid \
    'if [[ "${1:-}" == "-p" ]]; then' \
    '  [[ ",${MOCK_SIGNATURE_DEVICES:-}," == *",$(basename "${2}"),"* ]] && exit 0' \
    '  exit 2' \
    'fi' \
    'if [[ "$*" == *"-s TYPE"* ]]; then printf "%s\n" "${MOCK_MD_TYPE:-xfs}"; exit 0; fi' \
    'if [[ "$*" == *"-s LABEL"* ]]; then printf "%s\n" "${MOCK_MD_LABEL:-hbv4-local}"; exit 0; fi' \
    'exit 2'
  make_mock "${CASE_DIR}" mdadm \
    'case "${1:-}" in' \
    '  --examine)' \
    '    [[ ",${MOCK_RAID_METADATA_DEVICES:-}," == *",$(basename "${2}"),"* ]] && exit 0' \
    '    exit 1' \
    '    ;;' \
    '  --detail)' \
    '    printf "MD_LEVEL=%s\nMD_DEVICES=%s\n" "${MOCK_MD_LEVEL:-raid0}" "${MOCK_MD_DEVICES:-2}"' \
    '    ;;' \
    '  --create)' \
    '    printf "mdadm %s\n" "$*" >> "${MOCK_CASE_DIR}/mutations.log"' \
    '    ;;' \
    '  *) exit 99 ;;' \
    'esac'
  make_mock "${CASE_DIR}" mkfs.xfs \
    'printf "mkfs.xfs %s\n" "$*" >> "${MOCK_CASE_DIR}/mutations.log"'
  make_mock "${CASE_DIR}" mount \
    'printf "mount %s\n" "$*" >> "${MOCK_CASE_DIR}/mutations.log"'
  make_mock "${CASE_DIR}" mountpoint \
    '[[ "${MOCK_MOUNTED:-0}" == 1 ]]'
  make_mock "${CASE_DIR}" xfs_info \
    'printf "naming =version 2              bsize=4096   ascii-ci=0, ftype=%s\n" "${MOCK_XFS_FTYPE:-1}"'
}

run_helper()
{
  local case_dir="$1"
  shift
  local -a helper_args=()
  while (( $# > 0 )) && [[ "$1" == --* ]]; do
    helper_args+=("$1")
    shift
  done
  env \
    PATH="${case_dir}/bin:${PATH}" \
    MOCK_CASE_DIR="${case_dir}" \
    MOCK_MD_DEVICE="${case_dir}/dev/md/hbv4-local" \
    GEOS_HBV4_TEST_MODE=1 \
    GEOS_HBV4_TEST_DEV_ROOT="${case_dir}/dev" \
    GEOS_HBV4_TEST_BY_ID_DIR="${case_dir}/dev/disk/by-id" \
    GEOS_HBV4_TEST_AZURE_DISK_DIR="${case_dir}/dev/disk/azure" \
    GEOS_HBV4_TEST_AZURE_LOCAL_BY_SERIAL_DIR="${case_dir}/dev/disk/azure/local/by-serial" \
    GEOS_HBV4_TEST_SYS_CLASS_BLOCK_DIR="${case_dir}/sys/class/block" \
    GEOS_HBV4_TEST_PROC_SWAPS="${case_dir}/swaps" \
    GEOS_HBV4_TEST_MD_DEVICE="${case_dir}/dev/md/hbv4-local" \
    GEOS_HBV4_TEST_MOUNT_POINT="${case_dir}/mount/hbv4-local" \
    GEOS_HBV4_TEST_LOCK_FILE="${case_dir}/run/setup.lock" \
    "$@" \
    bash "${HELPER}" "${helper_args[@]}"
}

assert_no_destructive_mutation()
{
  local case_dir="$1"
  if grep -Eq '^(mdadm|mkfs\.xfs|mount) ' "${case_dir}/mutations.log"; then
    fail "$(basename "${case_dir}") executed a destructive command after rejection"
  fi
}

expect_success()
{
  local name="$1"
  shift
  new_case "${name}"
  if ! run_helper "${CASE_DIR}" "$@" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
    fail "${name} unexpectedly failed: $(<"${CASE_DIR}/stderr")"
  fi
}

expect_rejection()
{
  local name="$1"
  shift
  new_case "${name}"
  if run_helper "${CASE_DIR}" "$@" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
    fail "${name} unexpectedly succeeded"
  fi
  assert_no_destructive_mutation "${CASE_DIR}"
}

# A pristine pair succeeds, uses stable links in lexical order, and performs the
# one permitted create/format/mount sequence.  Its accepted-device diagnostics
# are also a regression for the live Azure shape: namespace-only lsblk output
# plus a padded `Microsoft NVMe Direct Disk` Identify Controller field.
expect_success fresh_success
if [[ "$(grep -c 'decision=accepted' "${CASE_DIR}/stdout")" != "2" ]]; then
  fail "fresh success did not report both accepted live-shape NVMe namespaces"
fi
grep -Fq 'model=Microsoft\ NVMe\ Direct\ Disk' "${CASE_DIR}/stdout" ||
  fail "fresh success did not preserve the multiword controller model"
grep -Fq "size_bytes=${EXPECTED_BYTES}" "${CASE_DIR}/stdout" ||
  fail "fresh success did not report the observed byte size"
if ! grep -Fq \
  "${CASE_DIR}/dev/disk/azure/local/by-serial/serial-nvme0n1 ${CASE_DIR}/dev/disk/azure/local/by-serial/serial-nvme1n1" \
  "${CASE_DIR}/mutations.log"; then
  fail "fresh success did not prefer deterministic Azure serial member links"
fi
for operation in mdadm mkfs.xfs mount; do
  grep -q "^${operation} " "${CASE_DIR}/mutations.log" ||
    fail "fresh success omitted ${operation}"
done
grep -Fq "LABEL=hbv4-local ${CASE_DIR}/mount/hbv4-local" "${CASE_DIR}/mutations.log" ||
  fail "fresh success did not mount the XFS filesystem by label"

# Generic by-id aliases remain a deterministic fallback for images where the
# Azure local/by-serial directory has not been populated.
new_case by_id_fallback
rm "${CASE_DIR}/dev/disk/azure/local/by-serial/"*
if ! run_helper "${CASE_DIR}" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
  fail "by-id fallback unexpectedly failed: $(<"${CASE_DIR}/stderr")"
fi
grep -Fq \
  "${CASE_DIR}/dev/disk/by-id/azure-nvme0n1 ${CASE_DIR}/dev/disk/by-id/azure-nvme1n1" \
  "${CASE_DIR}/mutations.log" ||
  fail "by-id fallback was not deterministic"

# Dry-run reports all planned state changes but no command shim sees a mutation.
expect_success dry_run --dry-run
assert_no_destructive_mutation "${CASE_DIR}"
grep -q 'DRY-RUN: mdadm' "${CASE_DIR}/stdout" ||
  fail "dry run did not report mdadm creation"
grep -q 'DRY-RUN: mkfs.xfs' "${CASE_DIR}/stdout" ||
  fail "dry run did not report XFS formatting"
grep -q 'DRY-RUN: mount' "${CASE_DIR}/stdout" ||
  fail "dry run did not report mounting"

# Candidate cardinality is an identity invariant: too few or too many matching
# devices is ambiguous and must stop before inspecting or mutating members.
for count in 0 1 3; do
  new_case "candidate_count_${count}"
  : > "${CASE_DIR}/discovery"
  for (( index=0; index<count; index++ )); do
    device="nvme${index}n1"
    : > "${CASE_DIR}/dev/${device}"
    mkdir -p "${CASE_DIR}/sys/class/block/${device}/holders"
    printf 'disk\n' > "${CASE_DIR}/type-${device}"
    printf '%s\n' "${EXPECTED_BYTES}" > "${CASE_DIR}/size-${device}"
    printf 'Microsoft NVMe Direct Disk\n' > "${CASE_DIR}/model-${device}"
    printf '%s disk\n' "${CASE_DIR}/dev/${device}" > "${CASE_DIR}/topology-${device}"
    printf '/dev/%s\n' "${device}" >> "${CASE_DIR}/discovery"
  done
  if run_helper "${CASE_DIR}" >"${CASE_DIR}/stdout-2" 2>"${CASE_DIR}/stderr-2"; then
    fail "candidate_count_${count} unexpectedly succeeded"
  fi
  assert_no_destructive_mutation "${CASE_DIR}"
done

# Identity mismatches remain ordinary rejected observations until the exact-two
# guard fails.  These fixtures protect both the model/size allowlist and the
# actionable diagnostics needed to distinguish a platform-shape change from a
# topology or signature rejection.
new_case rejected_controller_model
printf 'Unexpected NVMe Device\n' > "${CASE_DIR}/model-nvme1n1"
if run_helper "${CASE_DIR}" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
  fail "unexpected controller model succeeded"
fi
assert_no_destructive_mutation "${CASE_DIR}"
grep -Fq "device=${CASE_DIR}/dev/nvme1n1" "${CASE_DIR}/stderr" ||
  fail "controller-model diagnostic omitted the guarded device root"
grep -Fq 'model=Unexpected\ NVMe\ Device' "${CASE_DIR}/stderr" ||
  fail "controller-model rejection omitted the observed model"
grep -Fq 'reason=controller\ model\ does\ not\ match' "${CASE_DIR}/stderr" ||
  fail "controller-model rejection omitted its reason"

new_case rejected_byte_size
printf '%s\n' "$(( EXPECTED_BYTES + EXPECTED_BYTES / 100 + 1 ))" \
  > "${CASE_DIR}/size-nvme1n1"
if run_helper "${CASE_DIR}" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
  fail "out-of-tolerance byte size succeeded"
fi
assert_no_destructive_mutation "${CASE_DIR}"
grep -Fq 'reason=byte\ size\ is\ outside' "${CASE_DIR}/stderr" ||
  fail "byte-size rejection omitted its reason"

# Each negative fixture below models a state that could indicate user or OS
# ownership.  The correct behavior is refusal, never automatic cleanup.
new_case os_overlap
printf '%s\n' "${CASE_DIR}/dev/nvme0n1" > "${CASE_DIR}/chain-osdisk"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then fail "OS overlap succeeded"; fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case resource_overlap
printf '%s\n' "${CASE_DIR}/dev/resource" > "${CASE_DIR}/protected-mnt"
printf '%s\n' "${CASE_DIR}/dev/nvme1n1" > "${CASE_DIR}/chain-resource"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then fail "resource overlap succeeded"; fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case unmounted_azure_os_overlap
ln -s "../../nvme0n1" "${CASE_DIR}/dev/disk/azure/os"
printf '%s\n' "${CASE_DIR}/dev/nvme0n1" > "${CASE_DIR}/chain-os"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then
  fail "unmounted explicit Azure OS disk overlap succeeded"
fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case unmounted_azure_resource_overlap
ln -s "../../nvme1n1" "${CASE_DIR}/dev/disk/azure/resource"
printf '%s\n' "${CASE_DIR}/dev/nvme1n1" > "${CASE_DIR}/chain-resource"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then
  fail "unmounted explicit Azure resource disk overlap succeeded"
fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case mounted_candidate
printf '%s disk /scratch\n' "${CASE_DIR}/dev/nvme0n1" > "${CASE_DIR}/topology-nvme0n1"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then fail "mounted candidate succeeded"; fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case partitioned_candidate
printf '%s disk\n%s partition\n' \
  "${CASE_DIR}/dev/nvme0n1" "${CASE_DIR}/dev/nvme0n1p1" \
  > "${CASE_DIR}/topology-nvme0n1"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then fail "partitioned candidate succeeded"; fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case swap_candidate
printf '%s partition 1 1 -2\n' "${CASE_DIR}/dev/nvme0n1" >> "${CASE_DIR}/swaps"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then fail "swap candidate succeeded"; fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case holder_candidate
: > "${CASE_DIR}/sys/class/block/nvme0n1/holders/dm-0"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then fail "held candidate succeeded"; fi
assert_no_destructive_mutation "${CASE_DIR}"

expect_rejection filesystem_signature MOCK_SIGNATURE_DEVICES=nvme0n1
expect_rejection foreign_raid_metadata MOCK_RAID_METADATA_DEVICES=nvme1n1

# Destination ambiguity must also be rejected before mdadm. An unrelated mount,
# a nonempty directory exposed by a lost mount, or a symlink could otherwise
# hide or redirect OS-disk state after the candidate disks had been formatted.
expect_rejection unrelated_destination_mount MOCK_MOUNTED=1

new_case nonempty_destination
mkdir -p "${CASE_DIR}/mount/hbv4-local"
: > "${CASE_DIR}/mount/hbv4-local/unowned-state"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then
  fail "nonempty unmounted destination succeeded"
fi
assert_no_destructive_mutation "${CASE_DIR}"

new_case symlink_destination
mkdir -p "${CASE_DIR}/mount/other"
ln -s "${CASE_DIR}/mount/other" "${CASE_DIR}/mount/hbv4-local"
if run_helper "${CASE_DIR}" >/dev/null 2>&1; then
  fail "symbolic-link destination succeeded"
fi
assert_no_destructive_mutation "${CASE_DIR}"

prepare_existing_array()
{
  local case_dir="$1"
  : > "${case_dir}/dev/md/hbv4-local"
  mkdir -p \
    "${case_dir}/sys/class/block/hbv4-local/md" \
    "${case_dir}/sys/class/block/hbv4-local/slaves"
  printf 'raid0\n' > "${case_dir}/sys/class/block/hbv4-local/md/level"
  printf '2\n' > "${case_dir}/sys/class/block/hbv4-local/md/raid_disks"
  # Model the real RAID-0 sysfs contract: geometry and active slaves exist, but
  # the redundancy-only md/degraded attribute does not.
  : > "${case_dir}/sys/class/block/hbv4-local/slaves/nvme0n1"
  : > "${case_dir}/sys/class/block/hbv4-local/slaves/nvme1n1"
  for device in nvme0n1 nvme1n1; do
    printf '%s disk\n%s raid0\n' \
      "${case_dir}/dev/${device}" "${case_dir}/dev/md/hbv4-local" \
      > "${case_dir}/topology-${device}"
    : > "${case_dir}/sys/class/block/${device}/holders/hbv4-local"
  done
}

# A complete array is idempotent.  An unmounted instance is mounted without
# recreation; an already-correct mount performs no destructive operation.
new_case existing_unmounted
prepare_existing_array "${CASE_DIR}"
if ! run_helper "${CASE_DIR}" >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
  fail "complete unmounted array was rejected: $(<"${CASE_DIR}/stderr")"
fi
grep -q '^mount ' "${CASE_DIR}/mutations.log" ||
  fail "complete unmounted array was not mounted"
if grep -Eq '^(mdadm|mkfs\.xfs) ' "${CASE_DIR}/mutations.log"; then
  fail "complete unmounted array was recreated"
fi

new_case existing_mounted
prepare_existing_array "${CASE_DIR}"
if ! run_helper "${CASE_DIR}" MOCK_MOUNTED=1 >"${CASE_DIR}/stdout" 2>"${CASE_DIR}/stderr"; then
  fail "complete mounted array was rejected: $(<"${CASE_DIR}/stderr")"
fi
assert_no_destructive_mutation "${CASE_DIR}"

# Existing arrays must fail closed when geometry, active membership, exact
# members, filesystem, label, source, or mount options differ from the contract.
for fixture in partial_array foreign_members stale_label wrong_filesystem wrong_ftype wrong_mount_options; do
  new_case "${fixture}"
  prepare_existing_array "${CASE_DIR}"
  case "${fixture}" in
    partial_array)
      # Keep the declared two-device geometry while omitting one active slave;
      # the helper must reject this inconsistent member topology.
      rm "${CASE_DIR}/sys/class/block/hbv4-local/slaves/nvme1n1"
      fixture_env=()
      ;;
    foreign_members)
      rm "${CASE_DIR}/sys/class/block/hbv4-local/slaves/nvme1n1"
      : > "${CASE_DIR}/sys/class/block/hbv4-local/slaves/nvme9n1"
      fixture_env=()
      ;;
    stale_label)
      fixture_env=(MOCK_MD_LABEL=other)
      ;;
    wrong_filesystem)
      fixture_env=(MOCK_MD_TYPE=ext4)
      ;;
    wrong_ftype)
      fixture_env=(MOCK_XFS_FTYPE=0)
      ;;
    wrong_mount_options)
      fixture_env=("MOCK_MOUNTED=1" "MOCK_MOUNT_OPTIONS=rw,relatime")
      ;;
  esac
  if run_helper "${CASE_DIR}" "${fixture_env[@]}" >/dev/null 2>&1; then
    fail "${fixture} unexpectedly succeeded"
  fi
  assert_no_destructive_mutation "${CASE_DIR}"
done

# The flock shim returns the same immediate failure as `flock -n` under real
# contention.  This keeps the fixture portable to macOS, where util-linux flock
# is absent, without weakening the production nonblocking invocation contract.
expect_rejection lock_contention MOCK_FORCE_LOCKED=1

expect_rejection non_root MOCK_UID=1000

if (( failures > 0 )); then
  echo "${failures} HBv4 local-NVMe fixture(s) failed." >&2
  exit 1
fi

echo "HBv4 local-NVMe fixtures passed."
