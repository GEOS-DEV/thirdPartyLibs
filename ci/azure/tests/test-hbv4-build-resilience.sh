#!/usr/bin/env bash
# Exercise the HBv4 source-fetch retry and MPI-wrapper identity contracts.

set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
capture_wrapper="${repository_root}/scripts/hbv4/capture-mpi-wrapper-show.sh"
install_from_source="${repository_root}/scripts/hbv4/install-spack-from-source.sh"
collect_evidence="${repository_root}/scripts/hbv4/collect-build-evidence.sh"
container_validator="${repository_root}/scripts/hbv4/validate-hbv4-tpls"
dockerfile="${repository_root}/docker/tpl-ubuntu.Dockerfile"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/hbv4-build-resilience.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf 'test-hbv4-build-resilience: ERROR: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file=$1
  local expected=$2
  grep -Fq -- "$expected" "$file" || fail "missing '$expected' in $file"
}

# Keep the paid HBv4 build on the explicit setup, prefetch, and source-install
# path while leaving the portable Docker build on uberenv's existing path.
assert_contains "$dockerfile" '--setup-and-env-only'
assert_contains "$dockerfile" 'scripts/hbv4/install-spack-from-source.sh'
assert_contains "$dockerfile" "if [ \"\${HBV4_BUILD}\" = 1 ]; then"

# HDF5's CMake configuration reports true as ON, while older Autotools builds
# report yes. Accept both spellings, reject false values, and require the same
# guard during evidence collection and fresh-runner validation.
parallel_hdf5_pattern='Parallel HDF5:[[:space:]]*(yes|on)([[:space:]]|$)'
assert_contains "$collect_evidence" "parallel_hdf5_pattern='$parallel_hdf5_pattern'"
assert_contains "$container_validator" "parallel_hdf5_pattern='$parallel_hdf5_pattern'"
for enabled_value in 'Parallel HDF5: ON' 'Parallel HDF5: yes'; do
  grep -Eiq "$parallel_hdf5_pattern" <<<"$enabled_value" ||
    fail "parallel-HDF5 pattern rejected enabled value: $enabled_value"
done
if grep -Eiq "$parallel_hdf5_pattern" <<<'Parallel HDF5: OFF'; then
  fail 'parallel-HDF5 pattern accepted a disabled value'
fi

# Spack normalizes the Zen 4 preference to the x86-64-v4 architecture name in
# its lockfile. Require that target for every source-built spec while allowing
# generic x86_64 targets on compilers and other declared externals.
assert_contains "$container_validator" 'source_specs = [spec for spec in concrete_specs.values() if "external" not in spec]'
assert_contains "$container_validator" 'if source_targets != {"x86_64_v4"}:'
assert_contains "$container_validator" 'source-built Spack specs do not all target x86_64_v4'
if grep -Fq -- 'Spack concretization does not contain target=zen4' "$container_validator"; then
  fail 'validator still requires the non-concrete target spelling zen4'
fi

# h5pcc links shared HDF5 without embedding its installation path. The runtime
# check must add only the verified HDF5 prefix and retain strict MPI resolution.
assert_contains "$container_validator" '[[ "$h5pcc" == "$tpl_root"/* ]] || die "h5pcc resolves outside the TPL root: $h5pcc"'
assert_contains "$container_validator" 'compgen -G "$candidate/libhdf5.so*" >/dev/null || continue'
assert_contains "$container_validator" 'export LD_LIBRARY_PATH="$hdf5_loader_path${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"'
assert_contains "$container_validator" 'die "$target resolves libmpi outside $mpi_prefix: $library"'

# Reproduce Open MPI's symlink-sensitive wrapper layout. Invoking opal_wrapper
# directly fails; invoking the mpicc symlink succeeds because argv[0] is mpicc.
wrapper_root="${test_root}/wrapper"
mkdir -p "$wrapper_root"
cat >"${wrapper_root}/opal_wrapper" <<'EOF'
#!/usr/bin/env bash
if [[ ${0##*/} == mpicc && ${1:-} == --showme ]]; then
  printf 'gcc -march=native -mtune=native -lmpi\n'
  exit 0
fi
printf 'wrapper invoked with the wrong identity or arguments\n' >&2
exit 23
EOF
chmod +x "${wrapper_root}/opal_wrapper"
ln -s opal_wrapper "${wrapper_root}/mpicc"

if "${wrapper_root}/opal_wrapper" --showme >/dev/null 2>&1; then
  fail 'symlink-sensitive fixture unexpectedly accepted direct opal_wrapper invocation'
fi
bash "$capture_wrapper" openmpi "${wrapper_root}/mpicc" "${test_root}/openmpi-show.txt"
assert_contains "${test_root}/openmpi-show.txt" '-march=native -mtune=native'

# Model Spack with a deterministic command log: the first two source fetches
# fail, the third succeeds, and only then may the no-buildcache install run.
fake_root="${test_root}/fake-spack"
mkdir -p "${fake_root}/environment"
printf 'spack: {}\n' >"${fake_root}/environment/spack.yaml"
cat >"${fake_root}/spack" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_SPACK_LOG:?}"
: "${FAKE_SPACK_COUNT:?}"
printf '%s\n' "$*" >>"$FAKE_SPACK_LOG"
case " $* " in
  *' fetch '*)
    count=0
    [[ ! -f "$FAKE_SPACK_COUNT" ]] || count=$(<"$FAKE_SPACK_COUNT")
    count=$((count + 1))
    printf '%d\n' "$count" >"$FAKE_SPACK_COUNT"
    (( count >= ${FAKE_SPACK_SUCCEED_ON:-1} ))
    ;;
esac
EOF
chmod +x "${fake_root}/spack"

export FAKE_SPACK_LOG="${fake_root}/commands.log"
export FAKE_SPACK_COUNT="${fake_root}/fetch-count"
export FAKE_SPACK_SUCCEED_ON=3
HBV4_FETCH_ATTEMPTS=3 HBV4_FETCH_RETRY_DELAY_SECONDS=0 \
  bash "$install_from_source" \
    "${fake_root}/spack" "${fake_root}/environment" lvarray_hostconfig

[[ $(<"$FAKE_SPACK_COUNT") == 3 ]] || fail 'source prefetch did not retry exactly three times'
assert_contains "$FAKE_SPACK_LOG" '-D'
assert_contains "$FAKE_SPACK_LOG" 'concretize --fresh'
assert_contains "$FAKE_SPACK_LOG" '-k fetch --dependencies'
assert_contains "$FAKE_SPACK_LOG" '-k install --fresh --keep-stage --no-cache -p 4 -j 176 -u lvarray_hostconfig'

# Exhausting the bounded retry budget must fail closed and never compile.
: >"$FAKE_SPACK_LOG"
rm -f "$FAKE_SPACK_COUNT"
export FAKE_SPACK_SUCCEED_ON=99
if HBV4_FETCH_ATTEMPTS=2 HBV4_FETCH_RETRY_DELAY_SECONDS=0 \
    bash "$install_from_source" \
      "${fake_root}/spack" "${fake_root}/environment" lvarray_hostconfig; then
  fail 'source prefetch unexpectedly succeeded after exhausting its retry budget'
fi
if grep -Fq -- ' install ' "$FAKE_SPACK_LOG"; then
  fail 'Spack install ran after source prefetch exhausted its retry budget'
fi

printf 'HBv4 build resilience tests passed.\n'
