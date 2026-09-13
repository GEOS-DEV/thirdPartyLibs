#!/bin/bash

# Validate and, when necessary, install the Homebrew dependencies used by the
# macOS TPL configuration. Homebrew must already exist. This script
# intentionally never updates or upgrades Homebrew.

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
DEFAULT_MANIFEST="${SCRIPT_DIR}/spack_configs/macOS/homebrew-manifest.json"

MANIFEST=${DEFAULT_MANIFEST}
CHECK_ONLY=false
SPACK_CONFIG_OUT=
SPACK_CONFIG_TEMPLATE=${GEOS_TPL_SPACK_CONFIG_TEMPLATE:-${SCRIPT_DIR}/spack_configs/macOS/spack.yaml}

# These overrides allow the shell tests to inject deterministic stand-ins. In a
# normal shell, Homebrew is found through PATH or its standard install paths.
BREW_BIN=${GEOS_TPL_BREW_BIN:-}
PLUTIL_BIN=${GEOS_TPL_PLUTIL_BIN:-/usr/bin/plutil}
UNAME_BIN=${GEOS_TPL_UNAME_BIN:-/usr/bin/uname}
SW_VERS_BIN=${GEOS_TPL_SW_VERS_BIN:-/usr/bin/sw_vers}
XCRUN_BIN=${GEOS_TPL_XCRUN_BIN:-/usr/bin/xcrun}
CLANG_BIN=${GEOS_TPL_CLANG_BIN:-/usr/bin/clang}

WORK_DIR=
ERROR_COUNT=0
QUALIFICATION_BREW_PREFIX=
QUALIFICATION_CMAKE_VERSION=
QUALIFICATION_OPENMPI_VERSION=
QUALIFICATION_MPICH_VERSION=5.0.1
QUALIFICATION_PERL_VERSION=
HOST_BREW_PREFIX=
HOST_MACOS_VERSION=
HOST_SDK_VERSION=
HOST_CLANG_VERSION=
HOST_CLANG_BUILD=
HOST_CMAKE_VERSION=
HOST_PERL_VERSION=
MPI_PROVIDER=
MPI_VERSION=

declare -a FORMULA_NAMES=()
declare -a FORMULA_VERSIONS=()
declare -a FORMULA_VERSION_POLICIES=()
declare -a FORMULA_MIN_VERSIONS=()
declare -a FORMULA_PREFIXES=()
declare -a FORMULA_SHA256S=()
declare -a MISSING_FORMULAS=()

usage()
{
  cat <<'EOF'
Usage: scripts/setupMacOS-TPL-deps.bash [options]

Validate the Homebrew dependency set recorded in the checked-in manifest. Exact
pins and minimum-version policies are applied as declared. The manifest's host
and platform versions describe the qualification host; they are not exact
host-version gates. By default, missing formulas are installed only after the
complete preflight succeeds. Exact-pinned formula drift is never upgraded or
downgraded.

Options:
  --check-only          Validate without installing anything.
  --manifest PATH       Use an alternate manifest (primarily for testing).
  --spack-config-out PATH
                        Write a host-specific Spack environment file after
                        validation. The output contains the Homebrew prefix
                        and MPI provider; Uberenv discovers Apple Clang.
  -h, --help            Show this help text.
EOF
}

die()
{
  echo "ERROR: $*" >&2
  exit 1
}

record_error()
{
  echo "ERROR: $*" >&2
  ERROR_COUNT=$((ERROR_COUNT + 1))
}

cleanup()
{
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
    case "${WORK_DIR}" in
      "${TMPDIR:-/tmp}"/geos-macos-tpl-deps.*)
        rm -rf -- "${WORK_DIR}"
        ;;
    esac
  fi
}

is_nonnegative_integer()
{
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_sha256()
{
  [[ ${#1} -eq 64 ]] || return 1
  case "$1" in
    *[!0-9a-f]*) return 1 ;;
    *) return 0 ;;
  esac
}

version_at_least()
{
  awk -v actual="$1" -v minimum="$2" '
    BEGIN {
      actual_count = split(actual, actual_parts, "[.]")
      minimum_count = split(minimum, minimum_parts, "[.]")
      count = actual_count > minimum_count ? actual_count : minimum_count
      for (i = 1; i <= count; ++i) {
        actual_part = (i <= actual_count) ? actual_parts[i] + 0 : 0
        minimum_part = (i <= minimum_count) ? minimum_parts[i] + 0 : 0
        if (actual_part > minimum_part) exit 0
        if (actual_part < minimum_part) exit 1
      }
      exit 0
    }
  '
}

manifest_get()
{
  local key=$1
  local value
  if ! value=$("${PLUTIL_BIN}" -extract "${key}" raw -o - -- "${MANIFEST}" 2>/dev/null); then
    die "Manifest is missing '${key}' or it has an unsupported value type: ${MANIFEST}"
  fi
  printf '%s\n' "${value}"
}

require_equal()
{
  local label=$1
  local expected=$2
  local actual=$3
  if [[ "${actual}" != "${expected}" ]]; then
    record_error "${label} mismatch: expected '${expected}', found '${actual}'"
  fi
}

find_brew()
{
  local candidate

  if [[ -n "${BREW_BIN}" ]]; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    BREW_BIN=$(command -v brew)
    return 0
  fi

  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "${candidate}" ]]; then
      BREW_BIN=${candidate}
      return 0
    fi
  done

  BREW_BIN=/opt/homebrew/bin/brew
}

manifest_formula_prefix()
{
  local index=$1
  local prefix=${FORMULA_PREFIXES[${index}]}
  local suffix

  # Formula prefixes in the manifest are recorded against the qualification
  # Homebrew installation. Preserve their keg suffix when Homebrew is installed
  # somewhere else, such as /usr/local on Intel macOS.
  if [[ -n "${QUALIFICATION_BREW_PREFIX}" \
        && "${prefix}" == "${QUALIFICATION_BREW_PREFIX}"/* \
        && -n "${HOST_BREW_PREFIX}" ]]; then
    suffix=${prefix#${QUALIFICATION_BREW_PREFIX}}
    prefix="${HOST_BREW_PREFIX}${suffix}"
  fi
  printf '%s\n' "${prefix}"
}

formula_requirement()
{
  local index=$1
  local name=${FORMULA_NAMES[${index}]}
  local policy=${FORMULA_VERSION_POLICIES[${index}]}
  local version=${FORMULA_VERSIONS[${index}]}
  local minimum=${FORMULA_MIN_VERSIONS[${index}]}

  case "${policy}" in
    exact) printf '%s@%s\n' "${name}" "${version}" ;;
    minimum) printf '%s>=%s\n' "${name}" "${minimum}" ;;
    any) printf '%s\n' "${name}" ;;
  esac
}

write_spack_config()
{
  local escaped_brew
  local escaped_cmake escaped_qualification_cmake escaped_mpi
  local escaped_openmpi escaped_mpich escaped_qualification_openmpi escaped_qualification_mpich
  local escaped_perl escaped_qualification_perl
  local config_mpi_version config_openmpi_version config_mpich_version
  local generated_template generated_config mpi_config

  [[ -n "${SPACK_CONFIG_OUT}" ]] || return 0
  [[ -f "${SPACK_CONFIG_TEMPLATE}" ]] || die "Spack environment template does not exist: ${SPACK_CONFIG_TEMPLATE}"
  [[ "${SPACK_CONFIG_OUT}" != "${SPACK_CONFIG_TEMPLATE}" ]] || die "--spack-config-out must not overwrite the Spack environment template"

  case "${SPACK_CONFIG_OUT}" in
    */*) [[ -d "${SPACK_CONFIG_OUT%/*}" ]] || die "Spack config output directory does not exist: ${SPACK_CONFIG_OUT%/*}" ;;
  esac

  escaped_brew=$(printf '%s\n' "${HOST_BREW_PREFIX}" | sed 's/[|&\\]/\\&/g')
  escaped_cmake=$(printf '%s\n' "${HOST_CMAKE_VERSION}" | sed 's/[|&\\]/\\&/g')
  escaped_qualification_cmake=$(printf '%s\n' "${QUALIFICATION_CMAKE_VERSION}" | sed 's/[|&\\]/\\&/g')
  escaped_perl=$(printf '%s\n' "${HOST_PERL_VERSION}" | sed 's/[|&\\]/\\&/g')
  escaped_qualification_perl=$(printf '%s\n' "${QUALIFICATION_PERL_VERSION}" | sed 's/[|&\\]/\\&/g')
  config_mpi_version=${MPI_VERSION:-${QUALIFICATION_OPENMPI_VERSION}}
  escaped_mpi=$(printf '%s\n' "${config_mpi_version}" | sed 's/[|&\\]/\\&/g')
  escaped_qualification_openmpi=$(printf '%s\n' "${QUALIFICATION_OPENMPI_VERSION}" | sed 's/[|&\\]/\\&/g')
  escaped_qualification_mpich=$(printf '%s\n' "${QUALIFICATION_MPICH_VERSION}" | sed 's/[|&\\]/\\&/g')
  config_openmpi_version=${QUALIFICATION_OPENMPI_VERSION}
  config_mpich_version=${QUALIFICATION_MPICH_VERSION}
  if [[ "${MPI_PROVIDER}" == "open-mpi" && -n "${MPI_VERSION}" ]]; then
    config_openmpi_version=${MPI_VERSION}
  fi
  if [[ "${MPI_PROVIDER}" == "mpich" && -n "${MPI_VERSION}" ]]; then
    config_mpich_version=${MPI_VERSION}
  fi
  escaped_openmpi=$(printf '%s\n' "${config_openmpi_version}" | sed 's/[|&\\]/\\&/g')
  escaped_mpich=$(printf '%s\n' "${config_mpich_version}" | sed 's/[|&\\]/\\&/g')
  generated_template="${WORK_DIR}/spack-macos-template.yaml"
  generated_config="${WORK_DIR}/spack-macos.yaml"
  sed \
    -e "s|/opt/homebrew|${escaped_brew}|g" \
    -e "s|cmake@=${escaped_qualification_cmake}|cmake@=${escaped_cmake}|g" \
    -e "s|perl@=${escaped_qualification_perl}|perl@=${escaped_perl}|g" \
    -e "s|openmpi@=${escaped_qualification_openmpi}|openmpi@=${escaped_openmpi}|g" \
    -e "s|mpich@=${escaped_qualification_mpich}|mpich@=${escaped_mpich}|g" \
    -e 's/ os=tahoe//g' \
    "${SPACK_CONFIG_TEMPLATE}" >"${generated_template}"
  if ! awk \
    -v clang_version="${HOST_CLANG_VERSION}" \
    -v brew_prefix="${HOST_BREW_PREFIX}" '
      /^[[:space:]]*# GEOS_TPL_APPLE_CLANG_EXTERNAL$/ {
        found = 1
        print "      externals:"
        print "      - spec: \"apple-clang@=" clang_version " platform=darwin target=aarch64\""
        print "        prefix: /usr"
        print "        extra_attributes:"
        print "          compilers:"
        print "            c: /usr/bin/clang"
        print "            cxx: /usr/bin/clang++"
        print "          environment:"
        print "            set:"
        print "              AR: /usr/bin/ar"
        print "              RANLIB: /usr/bin/ranlib"
        print "              CMAKE_AR: /usr/bin/ar"
        print "              CMAKE_RANLIB: /usr/bin/ranlib"
        print "            prepend_path:"
        print "              PATH: /usr/bin"
        print "            remove_path:"
        print "              PATH: " brew_prefix "/opt/binutils/bin"
        next
      }
      { print }
      END {
        if (!found) exit 2
      }
    ' "${generated_template}" >"${generated_config}"; then
    die "Spack environment template is missing the Apple Clang insertion marker"
  fi
  if [[ "${MPI_PROVIDER}" == "mpich" ]]; then
    mpi_config="${WORK_DIR}/spack-macos-mpi.yaml"
    sed "s|require: \"openmpi@=${escaped_qualification_openmpi}\"|require: \"mpich@=${escaped_mpi}\"|g" \
      "${generated_config}" >"${mpi_config}"
    mv "${mpi_config}" "${generated_config}"
  fi
  mv "${generated_config}" "${SPACK_CONFIG_OUT}"
  echo "Wrote host-specific Spack environment: ${SPACK_CONFIG_OUT}"
}

parse_args()
{
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check-only)
        CHECK_ONLY=true
        shift
        ;;
      --manifest)
        [[ $# -ge 2 ]] || die "--manifest requires a path"
        MANIFEST=$2
        shift 2
        ;;
      --spack-config-out)
        [[ $# -ge 2 ]] || die "--spack-config-out requires a path"
        SPACK_CONFIG_OUT=$2
        shift 2
        ;;
      --spack-config-out=*)
        SPACK_CONFIG_OUT=${1#*=}
        [[ -n "${SPACK_CONFIG_OUT}" ]] || die "--spack-config-out requires a path"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument '$1'. Use --help for usage."
        ;;
    esac
  done
}

validate_manifest()
{
  local schema_version formula_count spack_built_count
  local i j name version policy policy_value minimum_version prefix sha
  local path_count relative_path seen

  [[ -f "${MANIFEST}" ]] || die "Manifest does not exist: ${MANIFEST}"
  "${PLUTIL_BIN}" -convert json -o - -- "${MANIFEST}" >/dev/null || die "Manifest is not valid JSON: ${MANIFEST}"

  schema_version=$(manifest_get schema_version)
  [[ "${schema_version}" == "1" ]] || die "Unsupported manifest schema '${schema_version}'"

  # Read all supported platform fields now so a malformed manifest fails before
  # any Homebrew command is attempted.
  manifest_get supported_platform.os >/dev/null
  manifest_get supported_platform.arch >/dev/null
  manifest_get supported_platform.macos_major >/dev/null
  manifest_get supported_platform.apple_clang_version >/dev/null
  manifest_get supported_platform.sdk_major >/dev/null
  manifest_get supported_platform.homebrew_prefix >/dev/null
  manifest_get qualification_host.macos_product_version >/dev/null
  manifest_get qualification_host.macos_build_version >/dev/null
  manifest_get qualification_host.apple_clang_build >/dev/null
  manifest_get qualification_host.sdk_version >/dev/null
  manifest_get qualification_host.homebrew_version >/dev/null

  formula_count=$(manifest_get formulae)
  is_nonnegative_integer "${formula_count}" || die "Manifest 'formulae' must be an array"
  [[ "${formula_count}" -gt 0 ]] || die "Manifest must declare at least one formula"

  i=0
  while [[ ${i} -lt ${formula_count} ]]; do
    name=$(manifest_get "formulae.${i}.name")
    policy=exact
    if policy_value=$("${PLUTIL_BIN}" -extract "formulae.${i}.version_policy" raw -o - -- "${MANIFEST}" 2>/dev/null); then
      policy=${policy_value}
    fi
    case "${policy}" in
      exact|any)
        minimum_version=
        ;;
      minimum)
        minimum_version=$(manifest_get "formulae.${i}.minimum_version")
        case "${minimum_version}" in
          ''|*[!0-9.]*) die "Formula '${name}' has an invalid minimum_version '${minimum_version}'" ;;
        esac
        ;;
      *)
        die "Formula '${name}' has an unsupported version_policy '${policy}'"
        ;;
    esac
    version=$(manifest_get "formulae.${i}.brew_version")
    prefix=$(manifest_get "formulae.${i}.prefix")
    sha=$(manifest_get "formulae.${i}.formula_sha256")

    case "${name}" in
      ''|*[!A-Za-z0-9_@+./-]*) die "Formula ${i} has an unsafe name '${name}'" ;;
    esac
    [[ -n "${version}" ]] || die "Formula '${name}' has an empty brew_version"
    [[ "${prefix}" == /* ]] || die "Formula '${name}' prefix must be absolute"
    is_sha256 "${sha}" || die "Formula '${name}' has an invalid formula_sha256"

    j=0
    while [[ ${j} -lt ${#FORMULA_NAMES[@]} ]]; do
      seen=${FORMULA_NAMES[${j}]}
      [[ "${seen}" != "${name}" ]] || die "Formula '${name}' is declared more than once"
      j=$((j + 1))
    done

    # These fields are consumed by the Spack configuration rather than this
    # installer, but validating them prevents the manifest from drifting into a
    # partial or ambiguous mapping.
    manifest_get "formulae.${i}.spack_package" >/dev/null
    manifest_get "formulae.${i}.spack_version" >/dev/null

    path_count=$(manifest_get "formulae.${i}.required_paths")
    is_nonnegative_integer "${path_count}" || die "Formula '${name}' required_paths must be an array"
    [[ "${path_count}" -gt 0 ]] || die "Formula '${name}' must declare at least one required path"
    j=0
    while [[ ${j} -lt ${path_count} ]]; do
      relative_path=$(manifest_get "formulae.${i}.required_paths.${j}")
      case "${relative_path}" in
        ''|/*|..|../*|*/../*|*/..) die "Formula '${name}' has unsafe required path '${relative_path}'" ;;
      esac
      j=$((j + 1))
    done

    FORMULA_NAMES[i]=${name}
    FORMULA_VERSIONS[i]=${version}
    FORMULA_VERSION_POLICIES[i]=${policy}
    FORMULA_MIN_VERSIONS[i]=${minimum_version}
    FORMULA_PREFIXES[i]=${prefix}
    FORMULA_SHA256S[i]=${sha}
    case "${name}" in
      cmake) QUALIFICATION_CMAKE_VERSION=${version} ;;
      open-mpi) QUALIFICATION_OPENMPI_VERSION=${version} ;;
      perl) QUALIFICATION_PERL_VERSION=${version} ;;
    esac
    i=$((i + 1))
  done

  spack_built_count=$(manifest_get spack_built)
  is_nonnegative_integer "${spack_built_count}" || die "Manifest 'spack_built' must be an array"
  [[ "${spack_built_count}" -gt 0 ]] || die "Manifest must document the Spack-built dependency set"
  i=0
  while [[ ${i} -lt ${spack_built_count} ]]; do
    manifest_get "spack_built.${i}.package" >/dev/null
    manifest_get "spack_built.${i}.version" >/dev/null
    i=$((i + 1))
  done
}

validate_platform()
{
  local clang_output clang_version clang_build brew_output brew_version
  local macos_major sdk_major qualification_macos_major qualification_sdk_major
  local qualification_brew_prefix

  find_brew
  [[ -x "${BREW_BIN}" ]] || die "Homebrew is required at ${BREW_BIN}; this script does not install Homebrew"
  [[ -x "${PLUTIL_BIN}" ]] || die "Required plist utility is missing: ${PLUTIL_BIN}"
  [[ -x "${UNAME_BIN}" && -x "${SW_VERS_BIN}" ]] || die "Required macOS platform tools are missing"
  [[ -x "${XCRUN_BIN}" && -x "${CLANG_BIN}" ]] || die "Apple Command Line Tools are required"

  require_equal "operating system" "$(manifest_get supported_platform.os)" "$("${UNAME_BIN}" -s)"
  require_equal "architecture" "$(manifest_get supported_platform.arch)" "$("${UNAME_BIN}" -m)"
  HOST_MACOS_VERSION=$("${SW_VERS_BIN}" -productVersion)
  macos_major=${HOST_MACOS_VERSION%%.*}
  qualification_macos_major=$(manifest_get supported_platform.macos_major)
  if [[ "${macos_major}" != "${qualification_macos_major}" ]]; then
    echo "INFO: macOS ${HOST_MACOS_VERSION} differs from qualification host major ${qualification_macos_major}; continuing"
  fi
  HOST_SDK_VERSION=$("${XCRUN_BIN}" --show-sdk-version)
  sdk_major=${HOST_SDK_VERSION%%.*}
  qualification_sdk_major=$(manifest_get supported_platform.sdk_major)
  if [[ "${sdk_major}" != "${qualification_sdk_major}" ]]; then
    echo "INFO: macOS SDK ${HOST_SDK_VERSION} differs from qualification host major ${qualification_sdk_major}; continuing"
  fi

  clang_output=$("${CLANG_BIN}" --version)
  clang_version=$(printf '%s\n' "${clang_output}" | sed -n 's/^Apple clang version \([^ ]*\).*/\1/p' | sed -n '1p')
  clang_build=$(printf '%s\n' "${clang_output}" | sed -n 's/^Apple clang version [^ ]* (clang-\([^)]*\)).*/\1/p' | sed -n '1p')
  [[ -n "${clang_version}" && -n "${clang_build}" ]] || record_error "Could not parse Apple Clang identity from '${CLANG_BIN} --version'"
  HOST_CLANG_VERSION=${clang_version}
  HOST_CLANG_BUILD=${clang_build}

  brew_output=$("${BREW_BIN}" --version)
  brew_version=$(printf '%s\n' "${brew_output}" | sed -n 's/^Homebrew //p' | sed -n '1p')
  [[ -n "${brew_version}" ]] || record_error "Could not parse Homebrew version from '${BREW_BIN} --version'"

  if ! HOST_BREW_PREFIX=$("${BREW_BIN}" --prefix); then
    record_error "Homebrew could not report its prefix"
  else
    qualification_brew_prefix=$(manifest_get supported_platform.homebrew_prefix)
    QUALIFICATION_BREW_PREFIX=${qualification_brew_prefix}
    if [[ "${HOST_BREW_PREFIX}" != "${qualification_brew_prefix}" ]]; then
      echo "INFO: Homebrew prefix is '${HOST_BREW_PREFIX}'; qualification host used '${qualification_brew_prefix}'"
    fi
  fi

  echo "Host details: macOS ${HOST_MACOS_VERSION} ($("${SW_VERS_BIN}" -buildVersion)), SDK ${HOST_SDK_VERSION}, Apple Clang ${clang_version} build ${clang_build}, Homebrew ${brew_version}"
  echo "Compiler defaults: C/C++=Apple Clang; Fortran=Homebrew GCC"

  [[ ${ERROR_COUNT} -eq 0 ]] || die "Platform preflight failed with ${ERROR_COUNT} error(s); no formulas were installed"
}

formula_metadata_matches()
{
  local index=$1
  local name expected_version expected_sha policy minimum_version info_file formula_count
  local full_name stable revision actual_version actual_sha

  name=${FORMULA_NAMES[${index}]}
  expected_version=${FORMULA_VERSIONS[${index}]}
  expected_sha=${FORMULA_SHA256S[${index}]}
  policy=${FORMULA_VERSION_POLICIES[${index}]}
  minimum_version=${FORMULA_MIN_VERSIONS[${index}]}
  info_file="${WORK_DIR}/formula-${index}.json"

  if ! "${BREW_BIN}" info --json=v2 "${name}" >"${info_file}"; then
    record_error "Homebrew could not inspect formula '${name}'"
    return 1
  fi
  if ! "${PLUTIL_BIN}" -convert json -o - -- "${info_file}" >/dev/null; then
    record_error "Homebrew returned invalid JSON for formula '${name}'"
    return 1
  fi
  if ! formula_count=$("${PLUTIL_BIN}" -extract formulae raw -o - -- "${info_file}" 2>/dev/null); then
    record_error "Homebrew metadata for '${name}' has no formulae array"
    return 1
  fi
  if [[ "${formula_count}" != "1" ]]; then
    record_error "Expected one Homebrew metadata record for '${name}', found '${formula_count}'"
    return 1
  fi

  full_name=$("${PLUTIL_BIN}" -extract formulae.0.full_name raw -o - -- "${info_file}" 2>/dev/null || true)
  stable=$("${PLUTIL_BIN}" -extract formulae.0.versions.stable raw -o - -- "${info_file}" 2>/dev/null || true)
  revision=$("${PLUTIL_BIN}" -extract formulae.0.revision raw -o - -- "${info_file}" 2>/dev/null || true)
  actual_sha=$("${PLUTIL_BIN}" -extract formulae.0.ruby_source_checksum.sha256 raw -o - -- "${info_file}" 2>/dev/null || true)

  if [[ "${full_name}" != "${name}" ]]; then
    record_error "Formula identity mismatch for '${name}': Homebrew reported '${full_name}'"
    return 1
  fi
  if [[ -z "${stable}" ]] || ! is_nonnegative_integer "${revision}"; then
    record_error "Formula '${name}' has invalid stable-version metadata"
    return 1
  fi
  actual_version=${stable}
  if [[ "${revision}" -gt 0 ]]; then
    actual_version="${stable}_${revision}"
  fi

  case "${policy}" in
    exact)
      if [[ "${actual_version}" != "${expected_version}" ]]; then
        record_error "Formula '${name}' metadata drift: expected version '${expected_version}', found '${actual_version}'"
        return 1
      fi
      if [[ "${actual_sha}" != "${expected_sha}" ]]; then
        record_error "Formula '${name}' source drift: expected checksum '${expected_sha}', found '${actual_sha}'"
        return 1
      fi
      ;;
    minimum)
      if ! version_at_least "${actual_version}" "${minimum_version}"; then
        record_error "Formula '${name}' is too old: requires at least '${minimum_version}', found '${actual_version}'"
        return 1
      fi
      ;;
    any)
      ;;
  esac
  return 0
}

installed_formula_version()
{
  local name=$1
  local line
  local -a fields
  line=$("${BREW_BIN}" list --versions "${name}" 2>/dev/null || true)
  if [[ -z "${line}" ]]; then
    return 1
  fi
  # Homebrew prints: <short formula name> <pkg-version>. Multiple installed
  # versions are rejected rather than choosing one implicitly.
  IFS=' ' read -r -a fields <<< "${line}"
  if [[ ${#fields[@]} -ne 2 ]]; then
    printf '__AMBIGUOUS__\n'
    return 0
  fi
  printf '%s\n' "${fields[1]}"
}

select_mpi_provider()
{
  local detected_version

  if detected_version=$(installed_formula_version mpich); then
    MPI_PROVIDER=mpich
    MPI_VERSION=${detected_version}
    return 0
  fi
  if detected_version=$(installed_formula_version open-mpi); then
    MPI_PROVIDER=open-mpi
    MPI_VERSION=${detected_version}
    return 0
  fi

  # OpenMPI is the fallback only when neither supported MPI is installed.
  MPI_PROVIDER=open-mpi
  MPI_VERSION=
}

validate_mpi_provider()
{
  local actual_prefix relative_path shared_library

  [[ "${MPI_PROVIDER}" == "mpich" ]] || return 0
  if [[ "${MPI_VERSION}" == "__AMBIGUOUS__" ]]; then
    record_error "MPI formula 'mpich' has multiple installed versions"
    return 1
  fi
  if ! actual_prefix=$("${BREW_BIN}" --prefix mpich); then
    record_error "Homebrew could not report the installed prefix for 'mpich'"
    return 1
  fi
  for relative_path in bin/mpicc bin/mpicxx bin/mpifort; do
    if [[ ! -e "${actual_prefix}/${relative_path}" ]]; then
      record_error "MPI formula 'mpich' is missing required path '${actual_prefix}/${relative_path}'"
    fi
  done
  shared_library=
  for shared_library in "${actual_prefix}"/lib/libmpi*.dylib; do
    if [[ -e "${shared_library}" ]]; then
      break
    fi
    shared_library=
  done
  if [[ -z "${shared_library}" ]]; then
    record_error "MPI formula 'mpich' is missing a shared MPI library under '${actual_prefix}/lib'"
  fi
  [[ ${ERROR_COUNT} -eq 0 ]] || die "MPI preflight failed; no formulas were installed"
}

should_skip_formula()
{
  local index=$1
  [[ "${FORMULA_NAMES[${index}]}" == "open-mpi" && "${MPI_PROVIDER}" == "mpich" ]]
}

validate_formula_installation()
{
  local index=$1
  local allow_missing=$2
  local name expected_version expected_prefix actual_version actual_prefix
  local policy minimum_version
  local path_count j relative_path role_suffix

  name=${FORMULA_NAMES[${index}]}
  expected_version=${FORMULA_VERSIONS[${index}]}
  policy=${FORMULA_VERSION_POLICIES[${index}]}
  minimum_version=${FORMULA_MIN_VERSIONS[${index}]}
  expected_prefix=$(manifest_formula_prefix "${index}")

  if ! actual_version=$(installed_formula_version "${name}"); then
    if [[ "${allow_missing}" == "true" ]]; then
      MISSING_FORMULAS[${#MISSING_FORMULAS[@]}]=${name}
      echo "MISSING: $(formula_requirement "${index}")"
      return 0
    fi
    record_error "Formula '${name}' is still missing after installation (requires $(formula_requirement "${index}"))"
    return 1
  fi
  if [[ "${actual_version}" == "__AMBIGUOUS__" ]]; then
    record_error "Formula '${name}' has multiple installed versions"
    return 1
  fi
  case "${policy}" in
    exact)
      if [[ "${actual_version}" != "${expected_version}" ]]; then
        record_error "Formula '${name}' receipt drift: expected '${expected_version}', found '${actual_version}'"
        return 1
      fi
      ;;
    minimum)
      if ! version_at_least "${actual_version}" "${minimum_version}"; then
        record_error "Formula '${name}' receipt is too old: requires at least '${minimum_version}', found '${actual_version}'"
        return 1
      fi
      ;;
    any)
      ;;
  esac

  if ! actual_prefix=$("${BREW_BIN}" --prefix "${name}"); then
    record_error "Homebrew could not report the installed prefix for '${name}'"
    return 1
  fi
  if [[ "${actual_prefix}" != "${expected_prefix}" ]]; then
    record_error "Formula '${name}' prefix mismatch: expected '${expected_prefix}', found '${actual_prefix}'"
    return 1
  fi

  case "${name}" in
    cmake) HOST_CMAKE_VERSION=${actual_version} ;;
    perl) HOST_PERL_VERSION=${actual_version} ;;
    open-mpi)
      MPI_VERSION=${actual_version}
      ;;
  esac
  role_suffix=
  if [[ "${name}" == "gcc" ]]; then
    role_suffix=" [Fortran compiler only]"
  fi

  path_count=$(manifest_get "formulae.${index}.required_paths")
  j=0
  while [[ ${j} -lt ${path_count} ]]; do
    relative_path=$(manifest_get "formulae.${index}.required_paths.${j}")
    if [[ ! -e "${expected_prefix}/${relative_path}" ]]; then
      record_error "Formula '${name}' is missing required path '${expected_prefix}/${relative_path}'"
    fi
    j=$((j + 1))
  done
  echo "OK: ${name}@${actual_version} (${actual_prefix})${role_suffix}"
  return 0
}

preflight_formulae()
{
  local i
  MISSING_FORMULAS=()
  i=0
  while [[ ${i} -lt ${#FORMULA_NAMES[@]} ]]; do
    if should_skip_formula "${i}"; then
      i=$((i + 1))
      continue
    fi
    # Check source identity for exact-pinned formulas even when already
    # installed. This makes stale API caches and silently rewritten formulas
    # visible drift.
    formula_metadata_matches "${i}" || true
    validate_formula_installation "${i}" true || true
    i=$((i + 1))
  done
  [[ ${ERROR_COUNT} -eq 0 ]] || die "Formula preflight failed with ${ERROR_COUNT} error(s); no formulas were installed"
}

revalidate_formulae()
{
  local i starting_errors
  starting_errors=${ERROR_COUNT}
  i=0
  while [[ ${i} -lt ${#FORMULA_NAMES[@]} ]]; do
    if should_skip_formula "${i}"; then
      i=$((i + 1))
      continue
    fi
    formula_metadata_matches "${i}" || true
    validate_formula_installation "${i}" false || true
    i=$((i + 1))
  done
  if [[ ${ERROR_COUNT} -ne ${starting_errors} ]]; then
    die "Post-install validation failed with $((ERROR_COUNT - starting_errors)) error(s)"
  fi
}

main()
{
  parse_args "$@"
  validate_manifest

  WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/geos-macos-tpl-deps.XXXXXX")
  trap cleanup EXIT HUP INT TERM

  export HOMEBREW_NO_ANALYTICS=1
  export HOMEBREW_NO_AUTO_UPDATE=1
  export HOMEBREW_NO_INSTALL_CLEANUP=1
  export HOMEBREW_NO_INSTALL_UPGRADE=1
  export HOMEBREW_NO_ENV_HINTS=1

  validate_platform
  select_mpi_provider
  validate_mpi_provider
  if [[ -n "${MPI_VERSION}" ]]; then
    echo "MPI provider: ${MPI_PROVIDER}@${MPI_VERSION}"
  else
    echo "MPI provider: open-mpi (fallback)"
  fi
  preflight_formulae

  if [[ ${#MISSING_FORMULAS[@]} -gt 0 ]]; then
    if [[ "${CHECK_ONLY}" == "true" ]]; then
      die "${#MISSING_FORMULAS[@]} required formula(s) are missing; check-only mode made no changes"
    fi
    echo "Installing preflighted formulas: ${MISSING_FORMULAS[*]}"
    if ! "${BREW_BIN}" install "${MISSING_FORMULAS[@]}"; then
      die "Homebrew failed while installing the preflighted formula set"
    fi
  fi

  revalidate_formulae
  write_spack_config
  echo "macOS Homebrew TPL dependency validation completed successfully."
}

main "$@"
