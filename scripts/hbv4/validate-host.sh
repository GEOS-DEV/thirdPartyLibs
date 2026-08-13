#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

die() { printf 'validate-host: ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf 'validate-host: %s\n' "$*" >&2; }
usage() {
  printf 'usage: %s --instance-type Standard_HB176rs_v4 --compiler-flags STRING --writable-path PATH [--mount PATH]\n' "$0" >&2
}

instance_type=
compiler_flags=
mount_path=/mnt/hbv4-local
writable_path=
while (($#)); do
  case "$1" in
    --instance-type) (($# >= 2)) || die 'missing instance type'; instance_type=$2; shift 2 ;;
    --compiler-flags) (($# >= 2)) || die 'missing compiler flags'; compiler_flags=$2; shift 2 ;;
    --mount) (($# >= 2)) || die 'missing mount path'; mount_path=$2; shift 2 ;;
    --writable-path) (($# >= 2)) || die 'missing writable path'; writable_path=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$writable_path" ]] || die '--writable-path is required'

[[ "$instance_type" =~ ^Standard_HB[0-9]+[A-Za-z0-9_-]*_v4$ ]] ||
  die "instance evidence is not an HBv4 SKU: $instance_type"
[[ "$compiler_flags" =~ (^|[[:space:]])(target=zen4|arch=zen4)([[:space:]]|$) ]] ||
  die 'build evidence does not contain an explicit Zen 4 target'
[[ "$compiler_flags" =~ (^|[[:space:]])-march=native([[:space:]]|$) ]] ||
  die 'compiler flags do not contain -march=native'
[[ "$compiler_flags" =~ (^|[[:space:]])-mtune=native([[:space:]]|$) ]] ||
  die 'compiler flags do not contain -mtune=native'
[[ ! "$compiler_flags" =~ (^|[[:space:]])-mcpu=native([[:space:]]|$) ]] ||
  die '-mcpu=native is forbidden'

command -v lscpu >/dev/null || die 'lscpu is required'
lscpu_output=$(lscpu)
grep -Eiq '^Model name:.*AMD EPYC.*9V33X' <<<"$lscpu_output" ||
  die 'CPU model is not AMD EPYC 9V33X HBv4 hardware'
grep -Eiq '^Flags:.*(^|[[:space:]])avx512f([[:space:]]|$)' <<<"$lscpu_output" ||
  die 'CPU lacks expected Zen 4 AVX-512 evidence'
cpu_count=$(awk -F: '/^CPU\(s\):/{gsub(/[[:space:]]/, "", $2); print $2; exit}' <<<"$lscpu_output")
[[ "$cpu_count" == 176 ]] || die "expected 176 visible HBv4 CPUs, found ${cpu_count:-unknown}"

command -v findmnt >/dev/null || die 'findmnt is required'
mount_record=$(findmnt -n -T "$mount_path" -o SOURCE,FSTYPE,TARGET) || die "$mount_path is not mounted"
IFS=' ' read -r mount_source mount_type mount_target <<<"$mount_record"
[[ "$mount_target" == "$mount_path" ]] || die "$mount_path is not a distinct mount point"
[[ "$mount_type" == xfs ]] || die "$mount_path must use XFS, found $mount_type"
mount_device=$(readlink -f "$mount_source") || die "cannot resolve mount source $mount_source"
mount_name=${mount_device##*/}
[[ "$mount_name" == md* && -d "/sys/block/$mount_name/md" ]] ||
  die "$mount_path source is not an md array: $mount_source"
[[ "$(<"/sys/block/$mount_name/md/level")" == raid0 ]] || die 'md array is not RAID0'
[[ "$(<"/sys/block/$mount_name/md/raid_disks")" == 2 ]] || die 'md array does not declare exactly two disks'
shopt -s nullglob
members=("/sys/block/$mount_name/slaves/"*)
shopt -u nullglob
[[ ${#members[@]} -eq 2 ]] || die "md array has ${#members[@]} members, expected exactly two"

# The XFS mount root intentionally remains root-owned. Prove write access in the
# caller's designated workload directory, and first prove that directory is
# still backed by the exact RAID mount validated above. This catches a lost
# mount without weakening the mount-root permission boundary.
[[ -d "$writable_path" ]] || die "writable path is not a directory: $writable_path"
writable_mount_record=$(findmnt -n -T "$writable_path" -o SOURCE,FSTYPE,TARGET) ||
  die "cannot resolve writable path mount: $writable_path"
IFS=' ' read -r writable_source writable_type writable_target <<<"$writable_mount_record"
[[ "$writable_target" == "$mount_path" && "$writable_type" == xfs ]] ||
  die "writable path is not backed by $mount_path XFS: $writable_path"
[[ "$(readlink -f "$writable_source")" == "$mount_device" ]] ||
  die "writable path is not backed by the validated RAID device: $writable_path"

probe=$(mktemp "$writable_path/.hbv4-write-test.XXXXXX") ||
  die "writable path rejected a file probe: $writable_path"
trap 'rm -f -- "$probe"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
printf 'hbv4 storage validation\n' >"$probe"
sync "$probe"
note "validated $instance_type: AMD EPYC 9V33X, 176 CPUs, Zen 4 flags, two-disk md RAID0 XFS at $mount_path, writable workload path $writable_path"
