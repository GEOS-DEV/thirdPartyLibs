#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
parallel_hdf5_pattern='Parallel HDF5:[[:space:]]*(yes|on)([[:space:]]|$)'

die() { printf 'collect-build-evidence: ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  cat >&2 <<'EOF'
usage: collect-build-evidence.sh OUTPUT_DIR PROVIDER SOURCE_SHA BASE_IMAGE MPI_CONFIGURE_ARGS_FILE SPACK_CONCRETIZATION_FILE

Required explicit variables: HBV4_TPL_SHA, HBV4_COMPILER_FLAGS
Optional explicit variables: HBV4_MPI_PREFIX, HBV4_MPI_VERSION,
HBV4_MPI_WRAPPER, HBV4_MPIEXEC, HBV4_H5PCC, HBV4_SPACK_BUILD_LOG

SPACK_CONCRETIZATION_FILE must be generated lock/spec evidence, not the input
manifest used to request concretization.
EOF
}

[[ $# -eq 6 ]] || { usage; exit 2; }
output_dir=$1
provider=$2
source_sha=$3
base_image=$4
configure_args_file=$5
spack_concretization_file=$6
: "${HBV4_TPL_SHA:?HBV4_TPL_SHA must be supplied explicitly}"
: "${HBV4_COMPILER_FLAGS:?HBV4_COMPILER_FLAGS must be supplied explicitly}"

case "$provider" in
  openmpi)
    default_prefix=/opt/openmpi/5.0.10
    default_version=5.0.10
    default_launcher=mpirun
    mpi_source_sha256=0acecc4fc218e5debdbcb8a41d182c6b0f1d29393015ed763b2a91d5d7374cc6
    ;;
  mpich)
    default_prefix=/opt/mpich/5.0.1
    default_version=5.0.1
    default_launcher=mpiexec
    mpi_source_sha256=8c1832a13ddacf071685069f5fadfd1f2877a29e1a628652892c65211b1f3327
    ;;
  *) die 'PROVIDER must be openmpi or mpich' ;;
esac
mpi_prefix_requested=${HBV4_MPI_PREFIX:-$default_prefix}
mpi_prefix=$(readlink -f "$mpi_prefix_requested") || die "cannot resolve MPI prefix: $mpi_prefix_requested"
[[ "$mpi_prefix" == "$default_prefix" ]] || die "MPI prefix must resolve to $default_prefix, found $mpi_prefix"
mpi_version=${HBV4_MPI_VERSION:-$default_version}
mpi_wrapper_requested=${HBV4_MPI_WRAPPER:-$mpi_prefix/bin/mpicc}
mpiexec_requested=${HBV4_MPIEXEC:-$mpi_prefix/bin/$default_launcher}
h5pcc=${HBV4_H5PCC:-$(command -v h5pcc || true)}

[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || die 'SOURCE_SHA must be a lowercase 40-hex commit'
[[ "$HBV4_TPL_SHA" =~ ^[0-9a-f]{40}$ ]] || die 'HBV4_TPL_SHA must be a lowercase 40-hex commit'
for scalar_name in base_image mpi_prefix mpi_version mpiexec_requested; do
  scalar=${!scalar_name}
  [[ "$scalar" =~ ^[A-Za-z0-9_./:@+-]+$ ]] || die "$scalar_name contains unsupported characters"
done
[[ "$HBV4_COMPILER_FLAGS" != *$'\n'* ]] || die 'HBV4_COMPILER_FLAGS must be one line'
[[ -f "$configure_args_file" && -r "$configure_args_file" ]] || die 'MPI configure args file is unreadable'
[[ -f "$spack_concretization_file" && -r "$spack_concretization_file" ]] || die 'Spack concretization file is unreadable'
[[ -x "$mpi_wrapper_requested" ]] || die "MPI wrapper is not executable: $mpi_wrapper_requested"
[[ -x "$mpiexec_requested" ]] || die "MPI launcher is not executable: $mpiexec_requested"
[[ "${mpiexec_requested##*/}" == "$default_launcher" ]] || die "requested MPI launcher must be $default_launcher for $provider"
mpi_wrapper_resolved=$(readlink -f "$mpi_wrapper_requested") || die 'cannot resolve MPI wrapper'
mpiexec=$(readlink -f "$mpiexec_requested") || die 'cannot resolve MPI launcher'
[[ "$mpi_wrapper_resolved" == "$mpi_prefix"/* ]] || die 'MPI wrapper resolves outside exact provider prefix'
[[ "$mpiexec" == "$mpi_prefix"/* ]] || die 'MPI launcher resolves outside exact provider prefix'
[[ -n "$h5pcc" && -x "$h5pcc" ]] || die "h5pcc is not executable: $h5pcc"
command -v lscpu >/dev/null || die 'lscpu is required for evidence capture'
command -v sha256sum >/dev/null || die 'sha256sum is required for evidence capture'
command -v python3 >/dev/null || die 'python3 is required for JSON evidence generation'
[[ "$base_image" =~ ^[A-Za-z0-9._:/+-]+@sha256:[0-9a-f]{64}$ ]] ||
  die 'BASE_IMAGE must be an immutable repository@sha256:<64 lowercase hex> reference'

mkdir -p -- "$output_dir"
[[ -d "$output_dir" && -w "$output_dir" ]] || die "output directory is not writable: $output_dir"
[[ -z "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
  die 'output directory must be empty to prevent stale or unreviewed evidence'

assert_sanitized() {
  local evidence_file=$1
  if grep -Eiq '(password|passwd|secret|token|api[_-]?key|authorization|cookie)[[:space:]]*[:=]|https?://[^/@[:space:]]+:[^/@[:space:]]+@' "$evidence_file"; then
    die "refusing evidence file with credential-like content: $evidence_file"
  fi
}
assert_sanitized "$configure_args_file"
assert_sanitized "$spack_concretization_file"
install -m 0444 "$configure_args_file" "$output_dir/mpi-configure-args.txt"
install -m 0444 "$spack_concretization_file" "$output_dir/spack-concretization.txt"
if [[ -n "${HBV4_SPACK_BUILD_LOG:-}" ]]; then
  [[ -f "$HBV4_SPACK_BUILD_LOG" && -r "$HBV4_SPACK_BUILD_LOG" ]] || die 'HBV4_SPACK_BUILD_LOG is unreadable'
  assert_sanitized "$HBV4_SPACK_BUILD_LOG"
  install -m 0444 "$HBV4_SPACK_BUILD_LOG" "$output_dir/spack-build.log"
fi
printf '%s\n' "$HBV4_COMPILER_FLAGS" >"$output_dir/compiler-flags.txt"
printf '%s\n' "$base_image" >"$output_dir/base-image.txt"
lscpu >"$output_dir/lscpu.txt"
bash "$script_dir/capture-mpi-wrapper-show.sh" \
  "$provider" "$mpi_wrapper_requested" "$output_dir/mpi-wrapper-show.txt" ||
  die 'MPI wrapper show command failed'
"$h5pcc" -showconfig >"$output_dir/hdf5-config.txt" 2>&1 || die 'h5pcc -showconfig failed'
grep -Eiq "$parallel_hdf5_pattern" "$output_dir/hdf5-config.txt" ||
  die 'h5pcc reports non-parallel HDF5'

python3 - "$output_dir/mpi-provider.json" "$provider" "$mpi_version" "$mpi_prefix" \
  "$configure_args_file" "$mpi_source_sha256" "$HBV4_TPL_SHA" "$base_image" \
  "$HBV4_COMPILER_FLAGS" <<'PY'
import json
import sys

(output, provider, version, prefix, configure_path, archive_sha256,
 tpl_source_sha, base_digest, compiler_flags) = sys.argv[1:]
with open(configure_path, encoding="utf-8") as stream:
    configure_arguments = stream.read()
record = {
    "schema_version": 1,
    "provider": provider,
    "version": version,
    "exact_prefix": prefix,
    "configure_arguments": configure_arguments,
    "archive_sha256": archive_sha256,
    "tpl_source_sha": tpl_source_sha,
    "base_digest": base_digest,
    "compiler_flags": compiler_flags,
}
with open(output, "w", encoding="utf-8") as stream:
    json.dump(record, stream, indent=2, sort_keys=True)
    stream.write("\n")
PY

cat >"$output_dir/manifest.json" <<EOF
{
  "schema_version": 1,
  "provider": "$provider",
  "mpi_version": "$mpi_version",
  "mpi_prefix": "$mpi_prefix",
  "mpi_launcher_requested": "$mpiexec_requested",
  "mpi_launcher_resolved": "$mpiexec",
  "source_sha": "$source_sha",
  "tpl_source_sha": "$HBV4_TPL_SHA",
  "mpi_source_sha256": "$mpi_source_sha256",
  "base_digest": "$base_image",
  "artifacts": {
    "compiler_flags": "compiler-flags.txt",
    "lscpu": "lscpu.txt",
    "mpi_configure_args": "mpi-configure-args.txt",
    "mpi_wrapper": "mpi-wrapper-show.txt",
    "hdf5_config": "hdf5-config.txt",
    "mpi_provider": "mpi-provider.json",
    "spack_concretization": "spack-concretization.txt",
    "spack_build_log": $(if [[ -n "${HBV4_SPACK_BUILD_LOG:-}" ]]; then printf '"spack-build.log"'; else printf 'null'; fi)
  }
}
EOF

checksum_tmp=$(mktemp "${TMPDIR:-/tmp}/hbv4-checksums.XXXXXX") || die 'cannot create checksum temporary file'
trap 'rm -f -- "$checksum_tmp"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
(
  cd -- "$output_dir"
  find . -maxdepth 1 -type f ! -name checksums.sha256 -print0 |
    LC_ALL=C sort -z | xargs -0 sha256sum >"$checksum_tmp"
)
install -m 0444 "$checksum_tmp" "$output_dir/checksums.sha256"
chmod 0444 "$output_dir"/*
printf 'build evidence written to %s\n' "$output_dir" >&2
