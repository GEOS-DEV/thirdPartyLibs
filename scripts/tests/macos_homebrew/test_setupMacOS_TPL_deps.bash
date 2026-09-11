#!/bin/bash

# Focused, dependency-free tests for setupMacOS-TPL-deps.bash. The production
# script runs against a fake Homebrew and fake platform tools; no real formula
# or Homebrew state is changed.

set -u

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "${TEST_DIR}/../../.." && pwd -P)
SCRIPT="${REPO_ROOT}/scripts/setupMacOS-TPL-deps.bash"
REAL_MANIFEST="${REPO_ROOT}/scripts/spack_configs/macOS/homebrew-manifest.json"
SPACK_YAML="${REPO_ROOT}/scripts/spack_configs/macOS/spack.yaml"
PLUTIL=/usr/bin/plutil

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/geos-macos-homebrew-tests.XXXXXX")
STATE="${TEST_ROOT}/state"
FAKE_BIN="${TEST_ROOT}/bin"
FAKE_PREFIX="${TEST_ROOT}/homebrew"
MANIFEST="${TEST_ROOT}/manifest.json"
LAST_OUTPUT="${TEST_ROOT}/last-output.txt"

PASS_COUNT=0
FAIL_COUNT=0

cleanup()
{
  case "${TEST_ROOT}" in
    "${TMPDIR:-/tmp}"/geos-macos-homebrew-tests.*)
      rm -rf -- "${TEST_ROOT}"
      ;;
  esac
}
trap cleanup EXIT HUP INT TERM

pass()
{
  echo "PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail()
{
  echo "FAIL: $1" >&2
  if [[ -f "${LAST_OUTPUT}" ]]; then
    sed 's/^/  | /' "${LAST_OUTPUT}" >&2
  fi
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

expect_success()
{
  local label=$1
  shift
  if "$@" >"${LAST_OUTPUT}" 2>&1; then
    pass "${label}"
  else
    fail "${label} (expected success)"
  fi
}

expect_failure()
{
  local label=$1
  shift
  if "$@" >"${LAST_OUTPUT}" 2>&1; then
    fail "${label} (expected failure)"
  else
    pass "${label}"
  fi
}

assert_file_contains()
{
  local label=$1
  local file=$2
  local pattern=$3
  if [[ -f "${file}" ]] && grep -F -q -- "${pattern}" "${file}"; then
    pass "${label}"
  else
    echo "Expected '${pattern}' in ${file}" >"${LAST_OUTPUT}"
    fail "${label}"
  fi
}

assert_file_contains_line()
{
  local label=$1
  local file=$2
  local line=$3
  if [[ -f "${file}" ]] && grep -F -x -q -- "${line}" "${file}"; then
    pass "${label}"
  else
    echo "Expected exact line '${line}' in ${file}" >"${LAST_OUTPUT}"
    fail "${label}"
  fi
}

assert_file_absent_or_empty()
{
  local label=$1
  local file=$2
  if [[ ! -s "${file}" ]]; then
    pass "${label}"
  else
    cp "${file}" "${LAST_OUTPUT}"
    fail "${label}"
  fi
}

formula_key()
{
  printf '%s\n' "$1" | sed 's#[/@]#_#g'
}

set_candidate()
{
  local formula=$1
  local stable=$2
  local revision=$3
  local sha=$4
  local key
  key=$(formula_key "${formula}")
  printf '%s\n' "${stable}" >"${STATE}/candidate_${key}_stable"
  printf '%s\n' "${revision}" >"${STATE}/candidate_${key}_revision"
  printf '%s\n' "${sha}" >"${STATE}/candidate_${key}_sha"
}

install_fixture()
{
  local formula=$1
  local version=$2
  local tool=$3
  local key prefix
  key=$(formula_key "${formula}")
  prefix="${FAKE_PREFIX}/opt/${formula}"
  printf '%s\n' "${version}" >"${STATE}/installed_${key}"
  mkdir -p "${prefix}/bin"
  : >"${prefix}/bin/${tool}"
}

create_fake_tools()
{
  mkdir -p "${STATE}" "${FAKE_BIN}" "${FAKE_PREFIX}/opt"

  cat >"${FAKE_BIN}/uname" <<'EOF'
#!/bin/bash
case "${1:-}" in
  -s) cat "${FAKE_BREW_STATE}/os" ;;
  -m) cat "${FAKE_BREW_STATE}/arch" ;;
  *) exit 2 ;;
esac
EOF

  cat >"${FAKE_BIN}/sw_vers" <<'EOF'
#!/bin/bash
case "${1:-}" in
  -productVersion) cat "${FAKE_BREW_STATE}/macos_version" ;;
  -buildVersion) cat "${FAKE_BREW_STATE}/macos_build" ;;
  *) exit 2 ;;
esac
EOF

  cat >"${FAKE_BIN}/xcrun" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--show-sdk-version" ]]; then
  cat "${FAKE_BREW_STATE}/sdk_version"
else
  exit 2
fi
EOF

  cat >"${FAKE_BIN}/clang" <<'EOF'
#!/bin/bash
if [[ "${1:-}" == "--version" ]]; then
  echo "Apple clang version $(cat "${FAKE_BREW_STATE}/clang_version") (clang-$(cat "${FAKE_BREW_STATE}/clang_build"))"
  echo "Target: arm64-apple-darwin"
else
  exit 2
fi
EOF

  cat >"${FAKE_BIN}/brew" <<'EOF'
#!/bin/bash
set -u

state=${FAKE_BREW_STATE:?}
prefix=${FAKE_HOMEBREW_PREFIX:?}
printf '%s\n' "$*" >>"${state}/commands.log"

key_for()
{
  printf '%s\n' "$1" | sed 's#[/@]#_#g'
}

case "${1:-}" in
  --version)
    echo "Homebrew $(cat "${state}/brew_version")"
    ;;
  --prefix)
    if [[ $# -eq 1 ]]; then
      echo "${prefix}"
    else
      echo "${prefix}/opt/$2"
    fi
    ;;
  info)
    [[ "${2:-}" == "--json=v2" ]] || exit 2
    formula=${3:?}
    key=$(key_for "${formula}")
    stable=$(cat "${state}/candidate_${key}_stable")
    revision=$(cat "${state}/candidate_${key}_revision")
    sha=$(cat "${state}/candidate_${key}_sha")
    printf '{"formulae":[{"full_name":"%s","versions":{"stable":"%s"},"revision":%s,"ruby_source_checksum":{"sha256":"%s"}}]}\n' \
      "${formula}" "${stable}" "${revision}" "${sha}"
    ;;
  list)
    [[ "${2:-}" == "--versions" ]] || exit 2
    formula=${3:?}
    key=$(key_for "${formula}")
    if [[ -f "${state}/installed_${key}" ]]; then
      echo "${formula##*/} $(cat "${state}/installed_${key}")"
    fi
    ;;
  install)
    shift
    install_count=0
    printf 'install-env:no-upgrade=%s:auto-update=%s:cleanup=%s\n' \
      "${HOMEBREW_NO_INSTALL_UPGRADE:-}" "${HOMEBREW_NO_AUTO_UPDATE:-}" "${HOMEBREW_NO_INSTALL_CLEANUP:-}" \
      >>"${state}/commands.log"
    for formula in "$@"; do
      install_count=$((install_count + 1))
      key=$(key_for "${formula}")
      stable=$(cat "${state}/candidate_${key}_stable")
      revision=$(cat "${state}/candidate_${key}_revision")
      version=${stable}
      if [[ "${revision}" -gt 0 ]]; then
        version="${stable}_${revision}"
      fi
      if [[ "${FAKE_INSTALL_WRONG:-0}" == "1" ]]; then
        version=99.0
      fi
      printf '%s\n' "${version}" >"${state}/installed_${key}"
      mkdir -p "${prefix}/opt/${formula}/bin"
      : >"${prefix}/opt/${formula}/bin/${formula}-tool"
      if [[ "${FAKE_INSTALL_FAIL_AFTER:-0}" -eq "${install_count}" ]]; then
        exit 42
      fi
    done
    ;;
  update|upgrade|cleanup)
    echo "Forbidden mutating command: $1" >&2
    exit 99
    ;;
  *)
    echo "Unexpected fake brew arguments: $*" >&2
    exit 2
    ;;
esac
EOF

  chmod +x "${FAKE_BIN}/uname" "${FAKE_BIN}/sw_vers" "${FAKE_BIN}/xcrun" \
    "${FAKE_BIN}/clang" "${FAKE_BIN}/brew"
}

write_manifest()
{
  cat >"${MANIFEST}" <<EOF
{
  "schema_version": 1,
  "supported_platform": {
    "os": "Darwin",
    "arch": "arm64",
    "macos_major": "26",
    "apple_clang_version": "17.0.0",
    "sdk_major": "26",
    "homebrew_prefix": "${FAKE_PREFIX}"
  },
  "qualification_host": {
    "macos_product_version": "26.5.1",
    "macos_build_version": "25F80",
    "apple_clang_build": "1700.6.3.2",
    "sdk_version": "26.2",
    "homebrew_version": "6.0.12"
  },
  "formulae": [
    {
      "name": "alpha",
      "brew_version": "1.0",
      "formula_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "prefix": "${FAKE_PREFIX}/opt/alpha",
      "spack_package": "alpha",
      "spack_version": "1.0",
      "required_paths": ["bin/alpha-tool"]
    },
    {
      "name": "beta",
      "brew_version": "2.0_1",
      "formula_sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "prefix": "${FAKE_PREFIX}/opt/beta",
      "spack_package": "beta",
      "spack_version": "2.0",
      "required_paths": ["bin/beta-tool"]
    },
    {
      "name": "cmake",
      "version_policy": "minimum",
      "minimum_version": "3.24",
      "brew_version": "4.4.3",
      "formula_sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "prefix": "${FAKE_PREFIX}/opt/cmake",
      "spack_package": "cmake",
      "spack_version": "4.4.3",
      "required_paths": ["bin/cmake-tool"]
    },
    {
      "name": "open-mpi",
      "version_policy": "any",
      "brew_version": "5.0.10",
      "formula_sha256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "prefix": "${FAKE_PREFIX}/opt/open-mpi",
      "spack_package": "openmpi",
      "spack_version": "5.0.10",
      "required_paths": ["bin/open-mpi-tool"]
    },
    {
      "name": "perl",
      "version_policy": "any",
      "brew_version": "5.44.0",
      "formula_sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "prefix": "${FAKE_PREFIX}/opt/perl",
      "spack_package": "perl",
      "spack_version": "5.44.0",
      "required_paths": ["bin/perl-tool"]
    }
  ],
  "spack_built": [
    {"package": "zlib", "version": "1.3.2"}
  ]
}
EOF
}

reset_state()
{
  rm -f "${STATE}"/installed_* "${STATE}/commands.log"
  rm -rf -- "${FAKE_PREFIX}/opt/alpha" "${FAKE_PREFIX}/opt/beta" \
    "${FAKE_PREFIX}/opt/cmake" "${FAKE_PREFIX}/opt/open-mpi" \
    "${FAKE_PREFIX}/opt/mpich" "${FAKE_PREFIX}/opt/perl"
  printf 'Darwin\n' >"${STATE}/os"
  printf 'arm64\n' >"${STATE}/arch"
  printf '26.99.7\n' >"${STATE}/macos_version"
  printf '25Z999\n' >"${STATE}/macos_build"
  printf '26.42\n' >"${STATE}/sdk_version"
  printf '17.0.0\n' >"${STATE}/clang_version"
  printf '1700.99.1\n' >"${STATE}/clang_build"
  printf '99.7.3\n' >"${STATE}/brew_version"
  set_candidate alpha 1.0 0 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  set_candidate beta 2.0 1 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  set_candidate cmake 4.4.3 0 cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
  set_candidate open-mpi 5.0.10 0 dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
  set_candidate perl 5.44.0 0 ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
  install_fixture alpha 1.0 alpha-tool
  install_fixture beta 2.0_1 beta-tool
  install_fixture cmake 4.4.3 cmake-tool
  install_fixture open-mpi 5.0.10 open-mpi-tool
  install_fixture perl 5.44.0 perl-tool
}

run_setup()
{
  FAKE_BREW_STATE="${STATE}" \
  FAKE_HOMEBREW_PREFIX="${FAKE_HOST_PREFIX:-${FAKE_PREFIX}}" \
  FAKE_INSTALL_WRONG="${FAKE_INSTALL_WRONG:-0}" \
  FAKE_INSTALL_FAIL_AFTER="${FAKE_INSTALL_FAIL_AFTER:-0}" \
  GEOS_TPL_BREW_BIN="${FAKE_BIN}/brew" \
  GEOS_TPL_UNAME_BIN="${FAKE_BIN}/uname" \
  GEOS_TPL_SW_VERS_BIN="${FAKE_BIN}/sw_vers" \
  GEOS_TPL_XCRUN_BIN="${FAKE_BIN}/xcrun" \
  GEOS_TPL_CLANG_BIN="${FAKE_BIN}/clang" \
  /bin/bash "${SCRIPT}" --manifest "${MANIFEST}" "$@"
}

run_setup_with_wrong_install()
{
  FAKE_INSTALL_WRONG=1 run_setup "$@"
}

spack_package_block()
{
  local package=$1
  awk -v heading="    ${package}:" '
    $0 == heading { found = 1; print; next }
    found && $0 ~ /^    [A-Za-z0-9_-]+:$/ { exit }
    found { print }
  ' "${SPACK_YAML}"
}

assert_manifest_field()
{
  local label=$1
  local key=$2
  local expected=$3
  local actual
  actual=$("${PLUTIL}" -extract "${key}" raw -o - "${REAL_MANIFEST}" 2>/dev/null || true)
  if [[ "${actual}" == "${expected}" ]]; then
    pass "${label}"
  else
    echo "Expected ${key}=${expected}, found ${actual}" >"${LAST_OUTPUT}"
    fail "${label}"
  fi
}

test_committed_manifest()
{
  local count i name found_forbidden spack_count
  local spack_package spack_version prefix block package version
  local external_count prefix_count package_heading_count
  if ! "${PLUTIL}" -convert json -o - "${REAL_MANIFEST}" >/dev/null; then
    fail "committed manifest is valid JSON"
    return
  fi
  count=$("${PLUTIL}" -extract formulae raw -o - "${REAL_MANIFEST}")
  if [[ "${count}" != "14" ]]; then
    echo "Expected 14 formulae, found ${count}" >"${LAST_OUTPUT}"
    fail "committed manifest formula count"
    return
  fi
  found_forbidden=false
  i=0
  while [[ ${i} -lt ${count} ]]; do
    name=$("${PLUTIL}" -extract "formulae.${i}.name" raw -o - "${REAL_MANIFEST}")
    case "${name}" in
      diffutils|zlib) found_forbidden=true ;;
    esac
    i=$((i + 1))
  done
  if [[ "${found_forbidden}" == "true" ]]; then
    echo "Perl, diffutils, or zlib appeared in Homebrew formulae" >"${LAST_OUTPUT}"
    fail "Spack-built packages are excluded from Homebrew formulae"
    return
  fi
  spack_count=$("${PLUTIL}" -extract spack_built raw -o - "${REAL_MANIFEST}")
  if [[ "${spack_count}" == "2" ]]; then
    pass "committed manifest schema and hybrid boundary"
  else
    echo "Expected 2 Spack-built packages, found ${spack_count}" >"${LAST_OUTPUT}"
    fail "committed manifest schema and hybrid boundary"
  fi

  i=0
  while [[ ${i} -lt ${count} ]]; do
    name=$("${PLUTIL}" -extract "formulae.${i}.name" raw -o - "${REAL_MANIFEST}")
    spack_package=$("${PLUTIL}" -extract "formulae.${i}.spack_package" raw -o - "${REAL_MANIFEST}")
    spack_version=$("${PLUTIL}" -extract "formulae.${i}.spack_version" raw -o - "${REAL_MANIFEST}")
    prefix=$("${PLUTIL}" -extract "formulae.${i}.prefix" raw -o - "${REAL_MANIFEST}")
    block=$(spack_package_block "${spack_package}")
    external_count=$(printf '%s\n' "${block}" | grep -E -c '^[[:space:]]+- spec:')
    prefix_count=$(printf '%s\n' "${block}" | grep -F -x -c -- "        prefix: ${prefix}")
    package_heading_count=$(grep -F -x -c -- "    ${spack_package}:" "${SPACK_YAML}")
    if [[ -n "${block}" ]] \
      && printf '%s\n' "${block}" | grep -F -q -- "buildable: false" \
      && printf '%s\n' "${block}" | grep -F -q -- "@=${spack_version}" \
      && [[ "${external_count}" == "1" ]] \
      && [[ "${prefix_count}" == "1" ]] \
      && [[ "${package_heading_count}" == "1" ]]; then
      pass "manifest ${name} maps to an exact non-buildable Spack external"
    else
      printf 'Manifest mapping for %s did not match Spack package block:\n%s\n' \
        "${name}" "${block}" >"${LAST_OUTPUT}"
      fail "manifest ${name} maps to an exact non-buildable Spack external"
    fi
    i=$((i + 1))
  done

  i=0
  while [[ ${i} -lt ${spack_count} ]]; do
    package=$("${PLUTIL}" -extract "spack_built.${i}.package" raw -o - "${REAL_MANIFEST}")
    version=$("${PLUTIL}" -extract "spack_built.${i}.version" raw -o - "${REAL_MANIFEST}")
    block=$(spack_package_block "${package}")
    if [[ -n "${block}" ]] \
      && printf '%s\n' "${block}" | grep -F -q -- "buildable: true" \
      && printf '%s\n' "${block}" | grep -F -q -- "@=${version}"; then
      pass "manifest ${package} remains Spack-built at the declared version"
    else
      printf 'Spack-built mapping for %s did not match package block:\n%s\n' \
        "${package}" "${block}" >"${LAST_OUTPUT}"
      fail "manifest ${package} remains Spack-built at the declared version"
    fi
    i=$((i + 1))
  done

  assert_manifest_field "GCC requires the versioned Fortran executable" \
    formulae.0.required_paths.0 bin/gfortran-16
  assert_manifest_field "OpenBLAS uses the selected-for-qualification version" \
    formulae.1.brew_version 0.3.34
  assert_manifest_field "readline maps its Homebrew patch release to Spack 8.3" \
    formulae.4.spack_version 8.3
  assert_manifest_field "CMake uses the Homebrew core formula" \
    formulae.3.name cmake
  assert_manifest_field "CMake uses the project minimum version" \
    formulae.3.minimum_version 3.24
  assert_manifest_field "MPI accepts an installed OpenMPI version" \
    formulae.2.version_policy any
  assert_manifest_field "binutils maps to the binutils Spack package" \
    formulae.11.spack_package binutils
  assert_manifest_field "Python uses the selected-for-qualification version" \
    formulae.12.brew_version 3.14.7
  assert_file_contains "macOS defaults C/C++ to Apple Clang" \
    "${SPACK_YAML}" '%[when=%c]c=apple-clang %[when=%cxx]cxx=apple-clang'
  assert_file_contains "macOS reserves GCC for Fortran" \
    "${SPACK_YAML}" 'require: "gcc@=16.2.0 languages:=fortran"'
  assert_file_contains "macOS Spack downloads use curl" \
    "${SPACK_YAML}" "url_fetch_method: curl"
}

create_fake_tools
write_manifest
test_committed_manifest

# Host releases newer than the recorded qualification host are accepted. The
# Homebrew formula versions and source checksums remain exact.
reset_state
expect_success "qualification-host macOS/SDK versions accept patch drift" run_setup --check-only

reset_state
expect_success "an exact installed contract is a no-op" run_setup
expect_success "a second exact run is idempotent" run_setup
if ! grep -q '^install ' "${STATE}/commands.log"; then
  pass "idempotent exact runs never invoke brew install"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "idempotent exact runs never invoke brew install"
fi
assert_file_contains "setup identifies Apple Clang as C/C++ default" \
  "${LAST_OUTPUT}" "Compiler defaults: C/C++=Apple Clang; Fortran=Homebrew GCC"
assert_file_contains "setup identifies the Fortran compiler" \
  "${LAST_OUTPUT}" "Fortran=Homebrew GCC"

reset_state
printf '3.24.0\n' >"${STATE}/installed_cmake"
rm -rf -- "${FAKE_PREFIX}/opt/cmake"
mkdir -p "${FAKE_PREFIX}/opt/cmake/bin"
: >"${FAKE_PREFIX}/opt/cmake/bin/cmake-tool"
expect_success "CMake at the project minimum is accepted" run_setup --check-only

reset_state
printf '3.23.9\n' >"${STATE}/installed_cmake"
rm -rf -- "${FAKE_PREFIX}/opt/cmake"
mkdir -p "${FAKE_PREFIX}/opt/cmake/bin"
: >"${FAKE_PREFIX}/opt/cmake/bin/cmake-tool"
expect_failure "CMake below the project minimum is rejected" run_setup --check-only

reset_state
set_candidate cmake 4.5.0 0 eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
expect_success "newer CMake metadata is accepted" run_setup --check-only

reset_state
set_candidate open-mpi 6.0.0 0 eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
expect_success "newer OpenMPI metadata is accepted" run_setup --check-only

reset_state
rm -f "${STATE}/installed_open-mpi"
rm -rf -- "${FAKE_PREFIX}/opt/open-mpi"
printf '5.0.1\n' >"${STATE}/installed_mpich"
mkdir -p "${FAKE_PREFIX}/opt/mpich/bin" "${FAKE_PREFIX}/opt/mpich/lib"
: >"${FAKE_PREFIX}/opt/mpich/bin/mpicc"
: >"${FAKE_PREFIX}/opt/mpich/bin/mpicxx"
: >"${FAKE_PREFIX}/opt/mpich/bin/mpifort"
: >"${FAKE_PREFIX}/opt/mpich/lib/libmpi.dylib"
GENERATED_MPI_CONFIG="${TEST_ROOT}/generated-mpich-spack.yaml"
expect_success "installed MPICH satisfies MPI without OpenMPI" run_setup --check-only --spack-config-out "${GENERATED_MPI_CONFIG}"
assert_file_contains "generated config selects MPICH" "${GENERATED_MPI_CONFIG}" 'require: "mpich@=5.0.1"'
if ! grep -F -q -- 'require: "openmpi@=' "${GENERATED_MPI_CONFIG}"; then
  pass "generated config does not require OpenMPI when MPICH is present"
else
  fail "generated config does not require OpenMPI when MPICH is present"
fi

reset_state
rm -f "${STATE}/installed_open-mpi"
rm -rf -- "${FAKE_PREFIX}/opt/open-mpi"
expect_success "OpenMPI is installed only as the MPI fallback" run_setup
assert_file_contains_line "fallback install receives open-mpi" "${STATE}/commands.log" "install open-mpi"

reset_state
printf '27.0\n' >"${STATE}/macos_version"
expect_success "newer macOS major is accepted" run_setup --check-only
if ! grep -q '^install ' "${STATE}/commands.log"; then
  pass "newer macOS check-only performs no install"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "newer macOS check-only performs no install"
fi

reset_state
printf 'x86_64\n' >"${STATE}/arch"
expect_failure "non-Apple-Silicon architecture is rejected" run_setup --check-only
if ! grep -q '^install ' "${STATE}/commands.log"; then
  pass "architecture rejection performs no install"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "architecture rejection performs no install"
fi

reset_state
printf '27.0\n' >"${STATE}/sdk_version"
expect_success "newer SDK major is accepted" run_setup --check-only
if ! grep -q '^install ' "${STATE}/commands.log"; then
  pass "newer SDK check-only performs no install"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "newer SDK check-only performs no install"
fi

reset_state
printf '21.0.0\n' >"${STATE}/clang_version"
expect_success "newer Apple Clang is accepted" run_setup --check-only
if grep -F -q -- 'Apple Clang 21.0.0 differs' "${LAST_OUTPUT}"; then
  fail "Apple Clang qualification notice is omitted"
else
  pass "Apple Clang qualification notice is omitted"
fi

reset_state
printf '21.0.0\n' >"${STATE}/clang_version"
GENERATED_CONFIG="${TEST_ROOT}/generated-spack.yaml"
expect_success "host-specific Spack config is generated" run_setup --check-only --spack-config-out "${GENERATED_CONFIG}"
assert_file_contains "generated config requires Apple Clang for C/C++" "${GENERATED_CONFIG}" '%[when=%c]c=apple-clang %[when=%cxx]cxx=apple-clang'
assert_file_contains "generated config uses detected Apple Clang" "${GENERATED_CONFIG}" "apple-clang@=21.0.0"
if ! grep -F -q -- 'apple-clang@=17.0.0' "${GENERATED_CONFIG}"; then
  pass "generated config does not use qualification-host Apple Clang"
else
  fail "generated config does not use qualification-host Apple Clang"
fi
assert_file_contains "generated config uses detected Perl" "${GENERATED_CONFIG}" "perl@=5.44.0"
assert_file_contains "generated config uses detected Homebrew prefix" "${GENERATED_CONFIG}" "prefix: ${FAKE_PREFIX}/opt/openblas"
if [[ -f "${GENERATED_CONFIG}" ]] && ! grep -F -q -- 'os=tahoe' "${GENERATED_CONFIG}"; then
  pass "generated config has no hard-coded macOS release"
else
  cp "${GENERATED_CONFIG}" "${LAST_OUTPUT}"
  fail "generated config has no hard-coded macOS release"
fi

reset_state
FAKE_HOST_PREFIX="${TEST_ROOT}/alternate-homebrew"
mkdir -p "${FAKE_HOST_PREFIX}/opt/alpha/bin" "${FAKE_HOST_PREFIX}/opt/beta/bin" \
  "${FAKE_HOST_PREFIX}/opt/cmake/bin" "${FAKE_HOST_PREFIX}/opt/open-mpi/bin" \
  "${FAKE_HOST_PREFIX}/opt/perl/bin"
: >"${FAKE_HOST_PREFIX}/opt/alpha/bin/alpha-tool"
: >"${FAKE_HOST_PREFIX}/opt/beta/bin/beta-tool"
: >"${FAKE_HOST_PREFIX}/opt/cmake/bin/cmake-tool"
: >"${FAKE_HOST_PREFIX}/opt/open-mpi/bin/open-mpi-tool"
: >"${FAKE_HOST_PREFIX}/opt/perl/bin/perl-tool"
expect_success "alternate Homebrew prefix is accepted" run_setup --check-only
FAKE_HOST_PREFIX=

reset_state
rm -f "${STATE}/installed_beta"
rm -rf -- "${FAKE_PREFIX}/opt/beta"
expect_failure "check-only reports an exact installable formula as missing" run_setup --check-only
if ! grep -q '^install ' "${STATE}/commands.log"; then
  pass "check-only never invokes brew install"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "check-only never invokes brew install"
fi

reset_state
rm -f "${STATE}/installed_beta"
rm -rf -- "${FAKE_PREFIX}/opt/beta"
expect_success "normal mode installs and revalidates only the missing formula" run_setup
assert_file_contains_line "brew install receives only beta" "${STATE}/commands.log" "install beta"
assert_file_contains "install disables upgrades and auto-update" "${STATE}/commands.log" "install-env:no-upgrade=1:auto-update=1:cleanup=1"
if ! grep -E -q '^(update|upgrade|cleanup)( |$)' "${STATE}/commands.log"; then
  pass "script never invokes brew update, upgrade, or cleanup"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "script never invokes brew update, upgrade, or cleanup"
fi

reset_state
printf '9.9\n' >"${STATE}/installed_beta"
expect_failure "installed receipt drift is rejected" run_setup
if ! grep -q '^install ' "${STATE}/commands.log"; then
  pass "receipt drift prevents all installation"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "receipt drift prevents all installation"
fi

reset_state
set_candidate beta 2.1 0 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
expect_failure "formula version metadata drift is rejected" run_setup

reset_state
set_candidate beta 2.0 1 cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
expect_failure "formula source checksum drift is rejected" run_setup

reset_state
rm -f "${FAKE_PREFIX}/opt/beta/bin/beta-tool"
expect_failure "missing required formula path is rejected" run_setup

reset_state
rm -f "${STATE}/installed_alpha"
rm -rf -- "${FAKE_PREFIX}/opt/alpha"
printf '9.9\n' >"${STATE}/installed_beta"
expect_failure "a later preflight error prevents installing an earlier missing formula" run_setup
if ! grep -q '^install ' "${STATE}/commands.log"; then
  pass "formula preflight is atomic"
else
  cp "${STATE}/commands.log" "${LAST_OUTPUT}"
  fail "formula preflight is atomic"
fi

reset_state
rm -f "${STATE}/installed_beta"
rm -rf -- "${FAKE_PREFIX}/opt/beta"
expect_failure "post-install receipt mismatch is detected" run_setup_with_wrong_install

reset_state
rm -f "${STATE}/installed_alpha" "${STATE}/installed_beta"
rm -rf -- "${FAKE_PREFIX}/opt/alpha" "${FAKE_PREFIX}/opt/beta"
FAKE_INSTALL_FAIL_AFTER=1 expect_failure \
  "a partial Homebrew install failure is surfaced" run_setup
if [[ -f "${STATE}/installed_alpha" && ! -f "${STATE}/installed_beta" ]]; then
  pass "partial failure fixture stopped between formula installs"
else
  echo "Expected only alpha to be installed by the partial-failure fixture" >"${LAST_OUTPUT}"
  fail "partial failure fixture stopped between formula installs"
fi

echo "${PASS_COUNT} passed; ${FAIL_COUNT} failed"
[[ ${FAIL_COUNT} -eq 0 ]]
