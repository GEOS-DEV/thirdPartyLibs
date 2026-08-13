#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

die() { printf 'install-spack-from-source: ERROR: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 3 ]] ||
  die 'usage: install-spack-from-source.sh SPACK_EXECUTABLE SPACK_ENVIRONMENT FINAL_PHASE'

spack_executable=$1
spack_environment=$2
final_phase=$3
fetch_attempts=${HBV4_FETCH_ATTEMPTS:-5}
retry_delay_seconds=${HBV4_FETCH_RETRY_DELAY_SECONDS:-10}
readonly concurrent_packages=4
readonly global_build_jobs=176

[[ -x "$spack_executable" ]] || die "Spack executable is not executable: $spack_executable"
[[ -d "$spack_environment" && -r "$spack_environment/spack.yaml" ]] ||
  die "Spack environment is missing or unreadable: $spack_environment"
[[ "$final_phase" =~ ^[A-Za-z0-9_+-]+$ ]] || die 'final phase contains unsupported characters'
if ! [[ "$fetch_attempts" =~ ^[1-9][0-9]*$ ]] || (( fetch_attempts > 10 )); then
  die 'HBV4_FETCH_ATTEMPTS must be between 1 and 10'
fi
if ! [[ "$retry_delay_seconds" =~ ^[0-9]+$ ]] || (( retry_delay_seconds > 300 )); then
  die 'HBV4_FETCH_RETRY_DELAY_SECONDS must be between 0 and 300'
fi

spack() {
  "$spack_executable" -D "$spack_environment" "$@"
}

# Concretize before starting any paid compilation, then fetch the complete DAG.
# Spack keeps successfully verified archives in its source cache, so a retry
# downloads only sources that did not complete on an earlier attempt.
spack concretize --fresh
spack spec --fresh --install-status --very-long

fetch_succeeded=false
for (( attempt = 1; attempt <= fetch_attempts; ++attempt )); do
  printf 'HBv4 source prefetch attempt %d/%d\n' "$attempt" "$fetch_attempts" >&2
  if spack -k fetch --dependencies; then
    fetch_succeeded=true
    break
  fi

  if (( attempt < fetch_attempts )); then
    delay=$((retry_delay_seconds * attempt))
    printf 'HBv4 source prefetch failed; retrying in %d seconds\n' "$delay" >&2
    sleep "$delay"
  fi
done

[[ "$fetch_succeeded" == true ]] ||
  die "source prefetch failed after $fetch_attempts attempts"

# The HBv4 manifests configure a source-only mirror, but every concrete node
# must still compile locally. --no-cache makes that policy explicit and blocks
# binary buildcache reuse independently of the mirror configuration. The pinned
# Spack new installer shares one 176-token jobserver across at most four active
# package builds, matching the 176 CPUs exposed to the HBv4 guest.
spack -k install --fresh --keep-stage --no-cache \
  -p "$concurrent_packages" -j "$global_build_jobs" -u "$final_phase"
