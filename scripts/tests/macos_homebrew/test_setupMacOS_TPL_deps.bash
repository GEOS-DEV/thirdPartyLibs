#!/bin/bash
# Exercise the setup contract with fake Homebrew/platform tools; no real installs.
set -euo pipefail

TEST_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "${TEST_DIR}/../../.." && pwd -P)
SCRIPT="${REPO_ROOT}/scripts/setupMacOS-TPL-deps.bash"
REAL_MANIFEST="${REPO_ROOT}/scripts/spack_configs/macOS/homebrew-manifest.json"
SPACK_YAML="${REPO_ROOT}/scripts/spack_configs/macOS/spack.yaml"
export GEOS_TPL_PLUTIL_BIN=${GEOS_TPL_PLUTIL_BIN:-/usr/bin/plutil}
TEST_ROOT=$(mktemp -d /tmp/geos-macos-homebrew-tests.XXXXXX)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export TMPDIR=${TEST_ROOT}
export FAKE_BREW_STATE="${TEST_ROOT}/state"
export FAKE_HOMEBREW_PREFIX="${TEST_ROOT}/homebrew"
STATE=${FAKE_BREW_STATE}
PREFIX=${FAKE_HOMEBREW_PREFIX}
BIN="${TEST_ROOT}/bin"
MANIFEST="${TEST_ROOT}/manifest.json"
OUTPUT="${TEST_ROOT}/output"
CONFIG="${TEST_ROOT}/spack.yaml"
BLOCK="${TEST_ROOT}/package.yaml"
SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
FORMULAE='perl 5.44.0 any - perl
m4 1.4.21 exact - m4
cmake 4.4.3 minimum 3.24 cmake
open-mpi 5.0.10 any - openmpi'
mkdir -p "${STATE}" "${BIN}" "${PREFIX}"
: >"${OUTPUT}"

fail()
{
  echo "FAIL: $*" >&2
  cat "${OUTPUT}" >&2
  exit 1
}

require() { "$@" || fail "$*"; }
contains() { require grep -Fq -- "$2" "$1"; }
get() { "${GEOS_TPL_PLUTIL_BIN}" -extract "$1" raw -o - -- "${2:-${MANIFEST}}"; }
no_install()
{
  if grep -Eq '^(install|update|upgrade|cleanup)( |$)' "${STATE}/commands.log"; then
    cat "${STATE}/commands.log" >&2
    fail "preflight must not mutate Homebrew"
  fi
}

cat >"${BIN}/platform" <<'EOF'
#!/bin/bash
case "${0##*/} $*" in
  'uname -s') echo Darwin ;;
  'uname -m') echo arm64 ;;
  'sw_vers -productVersion') echo 27.0 ;;
  'sw_vers -buildVersion') echo 26A1 ;;
  'xcrun --show-sdk-version') echo 27.0 ;;
  'clang --version') echo 'Apple clang version 21.0.0 (clang-2100.1)' ;;
  *) exit 2 ;;
esac
EOF
for tool in uname sw_vers xcrun clang; do
  ln -s platform "${BIN}/${tool}"
done

cat >"${BIN}/brew" <<'EOF'
#!/bin/bash
set -eu
state=${FAKE_BREW_STATE:?}
prefix=${FAKE_HOMEBREW_PREFIX:?}
echo "$*" >>"${state}/commands.log"
case "$1" in
  --version) echo 'Homebrew 99.0' ;;
  --prefix) echo "${prefix}${2:+/opt/$2}" ;;
  info)
    [[ "$2" == --json=v2 ]] || exit 2
    read -r version sha <"${state}/$3.candidate"
    printf '{"formulae":[{"full_name":"%s","versions":{"stable":"%s"},"revision":0,"ruby_source_checksum":{"sha256":"%s"}}]}\n' "$3" "${version}" "${sha}"
    ;;
  list)
    [[ "$2" == --versions ]] || exit 2
    if [[ -f "${state}/$3.installed" ]]; then
      echo "$3 $(cat "${state}/$3.installed")"
    fi
    ;;
  install)
    shift
    for formula in "$@"; do
      read -r version sha <"${state}/${formula}.candidate"
      echo "${version}" >"${state}/${formula}.installed"
      mkdir -p "${prefix}/opt/${formula}/bin"
      touch "${prefix}/opt/${formula}/bin/tool"
    done
    ;;
  *) echo "Unexpected brew command: $*" >&2; exit 2 ;;
esac
EOF
chmod +x "${BIN}/platform" "${BIN}/brew"

# Use the real Spack template so generation checks exercise its actual mappings.
cat >"${MANIFEST}" <<'EOF'
{
  "schema_version": 1,
  "supported_platform": {
    "os": "Darwin", "arch": "arm64", "macos_major": "26",
    "apple_clang_version": "17.0.0", "sdk_major": "26",
    "homebrew_prefix": "/opt/homebrew"
  },
  "qualification_host": {
    "macos_product_version": "26.5.1", "macos_build_version": "25F80",
    "apple_clang_build": "1700.6.3.2", "sdk_version": "26.2",
    "homebrew_version": "6.0.12"
  },
  "spack_built": [{"package": "zlib", "version": "1.3.2"}],
  "formulae": [
EOF
separator=
while read -r name version policy minimum package; do
  printf '%s\n' "${separator}" >>"${MANIFEST}"
  cat >>"${MANIFEST}" <<EOF
    {"name": "${name}", "brew_version": "${version}",
     "version_policy": "${policy}", "minimum_version": "${minimum}",
     "formula_sha256": "${SHA}", "prefix": "/opt/homebrew/opt/${name}",
     "spack_package": "${package}", "spack_version": "${version}",
     "required_paths": ["bin/tool"]}
EOF
  separator=,
done <<<"${FORMULAE}"
printf '\n  ]\n}\n' >>"${MANIFEST}"

candidate() { printf '%s %s\n' "$2" "${3:-${SHA}}" >"${STATE}/$1.candidate"; }
installed()
{
  echo "$2" >"${STATE}/$1.installed"
  mkdir -p "${PREFIX}/opt/$1/bin"
  touch "${PREFIX}/opt/$1/bin/tool"
}

reset_state()
{
  rm -f "${STATE}"/*.installed
  rm -rf -- "${PREFIX}/opt"
  : >"${STATE}/commands.log"
  while read -r name version rest; do
    candidate "${name}" "${version}"
    installed "${name}" "${version}"
  done <<<"${FORMULAE}"
}

run_setup()
{
  GEOS_TPL_BREW_BIN="${BIN}/brew" \
  GEOS_TPL_UNAME_BIN="${BIN}/uname" \
  GEOS_TPL_SW_VERS_BIN="${BIN}/sw_vers" \
  GEOS_TPL_XCRUN_BIN="${BIN}/xcrun" \
  GEOS_TPL_CLANG_BIN="${BIN}/clang" \
  /bin/bash "${SCRIPT}" --manifest "${MANIFEST}" "$@" >"${OUTPUT}" 2>&1
}
succeeds() { run_setup "$@" || fail "setup should succeed"; }
rejects() { if run_setup "$@"; then fail "setup should reject this fixture"; fi; }

# Check every committed mapping, without duplicating the manifest's version list.
for group in formulae spack_built; do
  count=$(get "${group}" "${REAL_MANIFEST}")
  for ((i = 0; i < count; i++)); do
    if [[ "${group}" == formulae ]]; then
      package=$(get "formulae.${i}.spack_package" "${REAL_MANIFEST}")
      version=$(get "formulae.${i}.spack_version" "${REAL_MANIFEST}")
      prefix=$(get "formulae.${i}.prefix" "${REAL_MANIFEST}")
      buildable=false
      spec="${package}@=${version}"
    else
      package=$(get "spack_built.${i}.package" "${REAL_MANIFEST}")
      version=$(get "spack_built.${i}.version" "${REAL_MANIFEST}")
      buildable=true
      spec="@=${version}"
    fi
    require test "$(grep -Fxc "    ${package}:" "${SPACK_YAML}")" = 1
    awk -v heading="    ${package}:" '
      $0 == heading { found = 1; next }
      found && /^    [A-Za-z0-9_-]+:$/ { exit }
      found { print }
    ' "${SPACK_YAML}" >"${BLOCK}"
    require grep -Fxq "      buildable: ${buildable}" "${BLOCK}"
    require awk -v spec="${spec}" '
      { gsub(/"/, " "); for (i = 1; i <= NF; i++) if ($i == spec) found = 1 }
      END { exit !found }
    ' "${BLOCK}"
    if [[ "${group}" == formulae ]]; then
      require test "$(grep -c '^[[:space:]]*- spec:' "${BLOCK}")" = 1
      require grep -Fxq "        prefix: ${prefix}" "${BLOCK}"
    fi
  done
done
echo 'PASS: committed manifest matches Spack externals and Spack-built versions'

reset_state
succeeds
no_install
echo 'PASS: qualified versions are accepted without installation'

reset_state
candidate m4 1.4.21 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
succeeds
contains "${OUTPUT}" 'formula file checksum differs from the qualification snapshot'
echo 'PASS: same-version formula checksum drift is reported and accepted'

reset_state
candidate m4 1.5
installed m4 1.5
candidate cmake 3.24.0
installed cmake 3.24.0
candidate open-mpi 4.1.8
installed open-mpi 4.1.8
installed perl 5.46.0
succeeds --check-only --spack-config-out "${CONFIG}"
for spec in 'apple-clang@=21.0.0' 'perl@=5.46.0' 'm4@=1.5' 'cmake@=3.24.0'; do
  contains "${CONFIG}" "${spec}"
done
contains "${CONFIG}" 'require: "openmpi@=4.1.8"'
contains "${CONFIG}" "prefix: ${PREFIX}/opt/m4"
no_install
echo 'PASS: newer versions, CMake minimum, OpenMPI, and detected Spack externals'

# Both live metadata and installed receipts enforce their respective floors.
for formula in m4 cmake; do
  if [[ "${formula}" == m4 ]]; then old=1.4.20; else old=3.23.9; fi
  for source in candidate installed; do
    reset_state
    rm -f "${STATE}/perl.installed"
    "${source}" "${formula}" "${old}"
    rejects
    contains "${OUTPUT}" "Formula '${formula}'"
    contains "${OUTPUT}" 'no formulas were installed'
    no_install
  done
done
echo 'PASS: older metadata or receipts prevent installation of earlier missing Perl'

reset_state
rm -f "${STATE}/open-mpi.installed"
installed mpich 5.0.1
mkdir -p "${PREFIX}/opt/mpich/lib"
for path in bin/mpicc bin/mpicxx bin/mpifort lib/libmpi.dylib; do
  touch "${PREFIX}/opt/mpich/${path}"
done
succeeds --check-only --spack-config-out "${CONFIG}"
contains "${CONFIG}" 'require: "mpich@=5.0.1"'
if grep -Fq 'require: "openmpi@=' "${CONFIG}"; then fail 'MPICH must replace OpenMPI'; fi
no_install
echo 'PASS: installed MPICH satisfies MPI and is selected in the generated config'

reset_state
rm -f "${STATE}/open-mpi.installed"
rejects --check-only
no_install
succeeds
require grep -Fxq 'install open-mpi' "${STATE}/commands.log"
echo 'PASS: check-only leaves missing MPI alone; normal setup installs the OpenMPI fallback'
