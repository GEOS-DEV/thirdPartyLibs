#!/bin/bash

# Validate and, when necessary, install the exact Homebrew dependencies used by
# the supported macOS TPL configuration. Homebrew itself and required taps must
# already exist. This script intentionally never updates or upgrades Homebrew.

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
DEFAULT_MANIFEST="${SCRIPT_DIR}/spack_configs/macOS/homebrew-manifest.json"

MANIFEST=${DEFAULT_MANIFEST}
CHECK_ONLY=false

# These overrides keep the production paths explicit while allowing the shell
# tests to inject deterministic stand-ins.
BREW_BIN=${GEOS_TPL_BREW_BIN:-/opt/homebrew/bin/brew}
PLUTIL_BIN=${GEOS_TPL_PLUTIL_BIN:-/usr/bin/plutil}
GIT_BIN=${GEOS_TPL_GIT_BIN:-/usr/bin/git}
UNAME_BIN=${GEOS_TPL_UNAME_BIN:-/usr/bin/uname}
SW_VERS_BIN=${GEOS_TPL_SW_VERS_BIN:-/usr/bin/sw_vers}
XCRUN_BIN=${GEOS_TPL_XCRUN_BIN:-/usr/bin/xcrun}
CLANG_BIN=${GEOS_TPL_CLANG_BIN:-/usr/bin/clang}

WORK_DIR=
ERROR_COUNT=0

declare -a TAP_NAMES=()
declare -a TAP_REMOTES=()
declare -a FORMULA_NAMES=()
declare -a FORMULA_VERSIONS=()
declare -a FORMULA_PREFIXES=()
declare -a FORMULA_SHA256S=()
declare -a MISSING_FORMULAS=()

usage()
{
  cat <<'EOF'
Usage: scripts/setupMacOS-TPL-deps.bash [options]

Validate the exact macOS and Homebrew dependency set recorded in the checked-in
manifest. By default, missing formulas are installed only after the complete
preflight succeeds. Existing version drift is never upgraded or downgraded.

Options:
  --check-only          Validate without installing anything.
  --manifest PATH       Use an alternate manifest (primarily for testing).
  -h, --help            Show this help text.

Prerequisite:
  brew tap geos-dev/geos
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
  local schema_version tap_count formula_count spack_built_count
  local i j name remote version prefix sha path_count relative_path seen

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

  tap_count=$(manifest_get taps)
  is_nonnegative_integer "${tap_count}" || die "Manifest 'taps' must be an array"
  [[ "${tap_count}" -gt 0 ]] || die "Manifest must declare at least one required tap"
  i=0
  while [[ ${i} -lt ${tap_count} ]]; do
    name=$(manifest_get "taps.${i}.name")
    remote=$(manifest_get "taps.${i}.remote")
    [[ -n "${name}" && -n "${remote}" ]] || die "Tap ${i} has an empty name or remote"
    TAP_NAMES[i]=${name}
    TAP_REMOTES[i]=${remote}
    i=$((i + 1))
  done

  formula_count=$(manifest_get formulae)
  is_nonnegative_integer "${formula_count}" || die "Manifest 'formulae' must be an array"
  [[ "${formula_count}" -gt 0 ]] || die "Manifest must declare at least one formula"

  i=0
  while [[ ${i} -lt ${formula_count} ]]; do
    name=$(manifest_get "formulae.${i}.name")
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
    FORMULA_PREFIXES[i]=${prefix}
    FORMULA_SHA256S[i]=${sha}
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
  local actual_brew_prefix macos_version macos_major sdk_version sdk_major

  [[ -x "${BREW_BIN}" ]] || die "Homebrew is required at ${BREW_BIN}; this script does not install Homebrew"
  [[ -x "${PLUTIL_BIN}" ]] || die "Required plist utility is missing: ${PLUTIL_BIN}"
  [[ -x "${GIT_BIN}" ]] || die "Required Git executable is missing: ${GIT_BIN}"
  [[ -x "${UNAME_BIN}" && -x "${SW_VERS_BIN}" ]] || die "Required macOS platform tools are missing"
  [[ -x "${XCRUN_BIN}" && -x "${CLANG_BIN}" ]] || die "Apple Command Line Tools are required"

  require_equal "operating system" "$(manifest_get supported_platform.os)" "$("${UNAME_BIN}" -s)"
  require_equal "architecture" "$(manifest_get supported_platform.arch)" "$("${UNAME_BIN}" -m)"
  macos_version=$("${SW_VERS_BIN}" -productVersion)
  macos_major=${macos_version%%.*}
  require_equal "macOS major version" "$(manifest_get supported_platform.macos_major)" "${macos_major}"
  sdk_version=$("${XCRUN_BIN}" --show-sdk-version)
  sdk_major=${sdk_version%%.*}
  require_equal "macOS SDK major version" "$(manifest_get supported_platform.sdk_major)" "${sdk_major}"

  clang_output=$("${CLANG_BIN}" --version)
  clang_version=$(printf '%s\n' "${clang_output}" | sed -n 's/^Apple clang version \([^ ]*\).*/\1/p' | sed -n '1p')
  clang_build=$(printf '%s\n' "${clang_output}" | sed -n 's/^Apple clang version [^ ]* (clang-\([^)]*\)).*/\1/p' | sed -n '1p')
  [[ -n "${clang_version}" && -n "${clang_build}" ]] || record_error "Could not parse Apple Clang identity from '${CLANG_BIN} --version'"
  require_equal "Apple Clang version" "$(manifest_get supported_platform.apple_clang_version)" "${clang_version}"

  brew_output=$("${BREW_BIN}" --version)
  brew_version=$(printf '%s\n' "${brew_output}" | sed -n 's/^Homebrew //p' | sed -n '1p')
  [[ -n "${brew_version}" ]] || record_error "Could not parse Homebrew version from '${BREW_BIN} --version'"

  if ! actual_brew_prefix=$("${BREW_BIN}" --prefix); then
    record_error "Homebrew could not report its prefix"
  else
    require_equal "Homebrew prefix" "$(manifest_get supported_platform.homebrew_prefix)" "${actual_brew_prefix}"
  fi

  echo "Host details: macOS ${macos_version} ($("${SW_VERS_BIN}" -buildVersion)), SDK ${sdk_version}, Apple Clang build ${clang_build}, Homebrew ${brew_version}"

  [[ ${ERROR_COUNT} -eq 0 ]] || die "Platform preflight failed with ${ERROR_COUNT} error(s); no formulas were installed"
}

validate_taps()
{
  local tap_output i name expected_remote repo actual_remote

  if ! tap_output=$("${BREW_BIN}" tap); then
    die "Homebrew could not list installed taps"
  fi

  i=0
  while [[ ${i} -lt ${#TAP_NAMES[@]} ]]; do
    name=${TAP_NAMES[${i}]}
    expected_remote=${TAP_REMOTES[${i}]}
    if ! printf '%s\n' "${tap_output}" | grep -F -x -q -- "${name}"; then
      record_error "Required tap '${name}' is absent; run: brew tap ${name}"
      i=$((i + 1))
      continue
    fi
    if ! repo=$("${BREW_BIN}" --repository "${name}"); then
      record_error "Homebrew could not locate required tap '${name}'"
      i=$((i + 1))
      continue
    fi
    if [[ ! -d "${repo}" ]]; then
      record_error "Tap '${name}' repository does not exist at '${repo}'"
      i=$((i + 1))
      continue
    fi
    if ! actual_remote=$("${GIT_BIN}" -C "${repo}" remote get-url origin); then
      record_error "Could not inspect Git remote for tap '${name}'"
      i=$((i + 1))
      continue
    fi
    require_equal "tap '${name}' remote" "${expected_remote}" "${actual_remote}"
    i=$((i + 1))
  done

  [[ ${ERROR_COUNT} -eq 0 ]] || die "Tap preflight failed with ${ERROR_COUNT} error(s); no formulas were installed"
}

formula_metadata_matches()
{
  local index=$1
  local name expected_version expected_sha info_file formula_count
  local full_name stable revision actual_version actual_sha

  name=${FORMULA_NAMES[${index}]}
  expected_version=${FORMULA_VERSIONS[${index}]}
  expected_sha=${FORMULA_SHA256S[${index}]}
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

  if [[ "${actual_version}" != "${expected_version}" ]]; then
    record_error "Formula '${name}' metadata drift: expected version '${expected_version}', found '${actual_version}'"
    return 1
  fi
  if [[ "${actual_sha}" != "${expected_sha}" ]]; then
    record_error "Formula '${name}' source drift: expected checksum '${expected_sha}', found '${actual_sha}'"
    return 1
  fi
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

validate_formula_installation()
{
  local index=$1
  local allow_missing=$2
  local name expected_version expected_prefix actual_version actual_prefix
  local path_count j relative_path

  name=${FORMULA_NAMES[${index}]}
  expected_version=${FORMULA_VERSIONS[${index}]}
  expected_prefix=${FORMULA_PREFIXES[${index}]}

  if ! actual_version=$(installed_formula_version "${name}"); then
    if [[ "${allow_missing}" == "true" ]]; then
      MISSING_FORMULAS[${#MISSING_FORMULAS[@]}]=${name}
      echo "MISSING: ${name}@${expected_version}"
      return 0
    fi
    record_error "Formula '${name}@${expected_version}' is still missing after installation"
    return 1
  fi
  if [[ "${actual_version}" == "__AMBIGUOUS__" ]]; then
    record_error "Formula '${name}' has multiple installed versions"
    return 1
  fi
  if [[ "${actual_version}" != "${expected_version}" ]]; then
    record_error "Formula '${name}' receipt drift: expected '${expected_version}', found '${actual_version}'"
    return 1
  fi

  if ! actual_prefix=$("${BREW_BIN}" --prefix "${name}"); then
    record_error "Homebrew could not report the installed prefix for '${name}'"
    return 1
  fi
  if [[ "${actual_prefix}" != "${expected_prefix}" ]]; then
    record_error "Formula '${name}' prefix mismatch: expected '${expected_prefix}', found '${actual_prefix}'"
    return 1
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
  echo "OK: ${name}@${actual_version} (${actual_prefix})"
  return 0
}

preflight_formulae()
{
  local i
  MISSING_FORMULAS=()
  i=0
  while [[ ${i} -lt ${#FORMULA_NAMES[@]} ]]; do
    # Check source identity even when the formula is already installed. This
    # makes stale API caches and silently rewritten formulas visible drift.
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
  validate_taps
  preflight_formulae

  if [[ ${#MISSING_FORMULAS[@]} -gt 0 ]]; then
    if [[ "${CHECK_ONLY}" == "true" ]]; then
      die "${#MISSING_FORMULAS[@]} required formula(s) are missing; check-only mode made no changes"
    fi
    echo "Installing exact preflighted formulas: ${MISSING_FORMULAS[*]}"
    if ! "${BREW_BIN}" install "${MISSING_FORMULAS[@]}"; then
      die "Homebrew failed while installing the preflighted formula set"
    fi
  fi

  revalidate_formulae
  echo "macOS Homebrew TPL dependency validation completed successfully."
}

main "$@"
