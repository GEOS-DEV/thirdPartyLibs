#!/usr/bin/env bash

set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)
cd -- "${repo_root}"

# Active build_images entries from .github/workflows/docker_build_tpls.yml.
# Fields: name|dockerfile|base_tag|base_repository|repository|gcc|clang|spec
MATRIX=(
'Ubuntu 24.04 - gcc 12|docker/tpl-ubuntu.Dockerfile|24.04-gcc12|geosx/ubuntu|geosx/ubuntu24.04-gcc12|12||~pygeosx ~docs %gcc-12'
'Ubuntu 24.04 - gcc 13 (docs)|docker/tpl-ubuntu.Dockerfile|24.04-gcc13|geosx/ubuntu|geosx/ubuntu24.04-gcc13|13||~pygeosx +docs %gcc-13'
'Ubuntu 24.04 - clang 19|docker/tpl-ubuntu.Dockerfile|24.04-clang19|geosx/ubuntu|geosx/ubuntu24.04-clang19||19|~pygeosx ~docs %clang-19'
'Ubuntu 24.04 - clang 20|docker/tpl-ubuntu.Dockerfile|24.04-clang20|geosx/ubuntu|geosx/ubuntu24.04-clang20||20|~pygeosx ~docs %clang-20'
'Rocky Linux 8 - gcc 12|docker/tpl-rockylinux.Dockerfile|8-gcc12|geosx/rockylinux|geosx/rockylinux8-gcc12|||~pygeosx ~docs %gcc-12'
'Rocky Linux 8 - gcc 13|docker/tpl-rockylinux.Dockerfile|8-gcc13|geosx/rockylinux|geosx/rockylinux8-gcc13|||~pygeosx ~docs %gcc-13'
'Rocky Linux 8 - clang 19|docker/tpl-rockylinux.Dockerfile|8-clang19|geosx/rockylinux|geosx/rockylinux8-clang19|||~pygeosx ~docs %clang-19'
'Rocky Linux 9 - clang 22|docker/tpl-rockylinux.Dockerfile|9-clang22|geosx/rockylinux|geosx/rockylinux9-clang22|||~pygeosx ~docs %clang-22'
'Ubuntu 24.04 - gcc 13 + CUDA 12.9.1|docker/tpl-ubuntu.Dockerfile|24.04-gcc13-cuda12.9.1|geosx/ubuntu|geosx/ubuntu24.04-gcc13-cuda12.9.1|13||+cuda cuda_arch=86,120 ~openmp ~pygeosx ~docs %gcc-13 ^cuda@12.9.1+allow-unsupported-compilers'
'Ubuntu 24.04 - clang 19 + CUDA 12.9.1|docker/tpl-ubuntu.Dockerfile|24.04-clang19-cuda12.9.1|geosx/ubuntu|geosx/ubuntu24.04-clang19-cuda12.9.1||19|+cuda cuda_arch=86,120 ~openmp ~pygeosx ~docs %clang-19 ^cuda@12.9.1+allow-unsupported-compilers'
'Rocky Linux 8 - gcc 13 + CUDA 12.9.1|docker/tpl-rockylinux.Dockerfile|8-gcc13-cuda12.9.1|geosx/rockylinux|geosx/rockylinux8-gcc13-cuda12.9.1|||+cuda cuda_arch=86,120 ~openmp ~pygeosx ~docs %gcc-13 ^cuda@12.9.1+allow-unsupported-compilers'
)

DOCKER_BASE_IMAGE_SHA=${DOCKER_BASE_IMAGE_SHA:-1c3c049b3f629d9d44838656fd306b2a0c04c9e8}
DOCKER_TAG=${DOCKER_TAG:-local}
COMMIT=${COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo HEAD)}
INSTALL_DIR_ROOT=${INSTALL_DIR_ROOT:-/opt/GEOS}
HOST_CONFIG=${HOST_CONFIG:-host-configs/environment.cmake}

keep_artifacts=0
dry_run=0
selected=()

job_name() { printf '%s' "${MATRIX[$1]%%|*}"; }

list_jobs() {
  printf 'Available CI jobs (--ci):\n'
  local i
  for i in "${!MATRIX[@]}"; do
    printf '  %2d  %s\n' "$((i + 1))" "$(job_name "$i")"
  done
}

usage() {
  cat <<EOF
Reproduce a thirdPartyLibs Docker CI build locally.

Usage: scripts/reproduce_ci.sh --ci "<job name>" [options]
       scripts/reproduce_ci.sh --all [options]
       scripts/reproduce_ci.sh --list

Job selection:
  --ci NAME          Build only this job. Repeatable. Matched exactly, or by a
                     unique case-insensitive substring (e.g. --ci "clang 22").
                     An index from --list also works (e.g. --ci 8).
  --all              Build every job in the matrix.
  --list             List the available jobs and exit.

Build settings (each also readable from the environment):
  --tag TAG          DOCKER_TAG            [${DOCKER_TAG}]
  --commit SHA       COMMIT                [${COMMIT}]
  --base-sha SHA     DOCKER_BASE_IMAGE_SHA [${DOCKER_BASE_IMAGE_SHA}]
  --install-dir DIR  INSTALL_DIR_ROOT      [${INSTALL_DIR_ROOT}]
  --host-config F    HOST_CONFIG           [${HOST_CONFIG}]

Other:
  --keep             Keep the image and buildx builder after a successful build
                     (default: both are removed to reclaim disk).
  --dry-run          Print what would be built, then exit.
  -h, --help         Show this help.

EOF
  list_jobs
}

# Resolve one --ci argument to a matrix index; prints the index on success.
resolve_job() {
  local query=$1 i matches=()

  # a bare index from --list
  if [[ ${query} =~ ^[0-9]+$ ]]; then
    if (( query >= 1 && query <= ${#MATRIX[@]} )); then
      printf '%s' "$((query - 1))"
      return 0
    fi
    printf 'No such job index: %s\n\n' "${query}" >&2
    return 1
  fi

  # exact name
  for i in "${!MATRIX[@]}"; do
    [[ $(job_name "$i") == "${query}" ]] && { printf '%s' "$i"; return 0; }
  done

  # unique case-insensitive substring
  local lower=${query,,} name_lower
  for i in "${!MATRIX[@]}"; do
    name_lower=$(job_name "$i")
    name_lower=${name_lower,,}
    [[ ${name_lower} == *"${lower}"* ]] && matches+=("$i")
  done

  if (( ${#matches[@]} == 1 )); then
    printf '%s' "${matches[0]}"
    return 0
  fi
  if (( ${#matches[@]} > 1 )); then
    printf 'Ambiguous job: "%s" matches %d jobs:\n' "${query}" "${#matches[@]}" >&2
    for i in "${matches[@]}"; do printf '  %s\n' "$(job_name "$i")" >&2; done
    printf '\n' >&2
    return 1
  fi

  printf 'Unknown job: "%s"\n\n' "${query}" >&2
  return 1
}

while (( $# )); do
  case $1 in
    --ci)           [[ ${2:-} ]] || { echo "--ci needs a job name" >&2; exit 2; }
                    selected+=("$2"); shift 2 ;;
    --ci=*)         selected+=("${1#*=}"); shift ;;
    --all)          selected=(__all__); shift ;;
    --list)         list_jobs; exit 0 ;;
    --tag)          DOCKER_TAG=$2; shift 2 ;;
    --commit)       COMMIT=$2; shift 2 ;;
    --base-sha)     DOCKER_BASE_IMAGE_SHA=$2; shift 2 ;;
    --install-dir)  INSTALL_DIR_ROOT=$2; shift 2 ;;
    --host-config)  HOST_CONFIG=$2; shift 2 ;;
    --keep)         keep_artifacts=1; shift ;;
    --dry-run)      dry_run=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if (( ${#selected[@]} == 0 )); then
  printf 'Nothing to do: pass --ci "<job name>" (or --all).\n\n' >&2
  usage >&2
  exit 2
fi

# Resolve the selection to matrix indices.
indices=()
if [[ ${selected[0]} == __all__ ]]; then
  indices=("${!MATRIX[@]}")
else
  resolve_failed=0
  for query in "${selected[@]}"; do
    if idx=$(resolve_job "${query}"); then
      indices+=("${idx}")
    else
      resolve_failed=1
    fi
  done
  if (( resolve_failed )); then
    list_jobs >&2
    exit 1
  fi
fi

command -v docker >/dev/null || {
  echo "docker is required" >&2
  exit 127
}
export DOCKER_BUILDKIT=1

failed=0
failed_builders=()

build() {
  local index=$1 name=$2 dockerfile=$3 base_tag=$4 base_repository=$5 repository=$6
  local gcc=$7 clang=$8 spec=$9
  local builder="reproduce-ci-$$-${index}" image="${repository}:${DOCKER_TAG}"
  local cleanup_failed=0

  printf '\n==> %s\n' "${name}"

  if (( dry_run )); then
    printf '    dockerfile   %s\n' "${dockerfile}"
    printf '    base image   %s:%s-%s\n' "${base_repository}" "${base_tag}" "${DOCKER_BASE_IMAGE_SHA}"
    printf '    repository   %s\n' "${repository}"
    printf '    tag          %s\n' "${DOCKER_TAG}"
    printf '    spec         %s\n' "${spec}"
    [[ ${gcc} ]] && printf '    gcc          %s\n' "${gcc}"
    [[ ${clang} ]] && printf '    clang        %s\n' "${clang}"
    printf '    commit       %s\n' "${COMMIT}"
    printf '    install dir  %s\n' "${INSTALL_DIR_ROOT}"
    printf '    host config  %s\n' "${HOST_CONFIG}"
    return
  fi

  if ! docker buildx create --name "${builder}" --driver docker-container --bootstrap >/dev/null; then
    printf 'FAILED TO CREATE BUILDER: %s\n' "${name}" >&2
    failed=1
    return
  fi

  if ! TPL_DOCKERFILE=${dockerfile} \
    DOCKER_REPOSITORY=${repository} \
    DOCKER_BASE_IMAGE="${base_repository}:${base_tag}-${DOCKER_BASE_IMAGE_SHA}" \
    GCC_VERSION=${gcc} \
    CLANG_VERSION=${clang} \
    INSTALL_DIR_ROOT=${INSTALL_DIR_ROOT} \
    HOST_CONFIG=${HOST_CONFIG} \
    SPEC=${spec} \
    COMMIT=${COMMIT} \
    BUILD_DIR=${repo_root} \
    DOCKER_TAG=${DOCKER_TAG} \
    DOCKER_BUILDER=${builder} \
    DOCKER_LOAD=1 \
    bash -x scripts/docker-build.sh; then
    printf 'FAILED: %s (builder retained: %s)\n' "${name}" "${builder}" >&2
    failed=1
    failed_builders+=("${builder}")
    return
  fi

  if (( keep_artifacts )); then
    printf 'PASSED: %s (image %s and builder %s retained)\n' "${name}" "${image}" "${builder}"
    return
  fi

  if docker image inspect "${image}" >/dev/null 2>&1; then
    if ! docker image rm -f "${image}" >/dev/null; then
      printf 'FAILED TO REMOVE IMAGE: %s\n' "${image}" >&2
      cleanup_failed=1
    fi
  fi
  if ! docker buildx rm -f "${builder}" >/dev/null; then
    printf 'FAILED TO REMOVE BUILDER: %s\n' "${builder}" >&2
    cleanup_failed=1
  fi

  if (( cleanup_failed )); then
    failed=1
    failed_builders+=("${builder}")
  else
    printf 'PASSED: %s (image and build cache removed)\n' "${name}"
  fi
}

printf 'Selected %d of %d job(s).\n' "${#indices[@]}" "${#MATRIX[@]}"

row=0
for idx in "${indices[@]}"; do
  row=$((row + 1))
  IFS='|' read -r name dockerfile base_tag base_repository repository gcc clang spec \
    <<<"${MATRIX[${idx}]}"
  build "${row}" "${name}" "${dockerfile}" "${base_tag}" "${base_repository}" \
    "${repository}" "${gcc}" "${clang}" "${spec}"
done

if (( dry_run )); then
  printf '\nDry run: nothing was built.\n'
  exit 0
fi

if (( failed )); then
  echo "One or more Docker CI builds failed." >&2
  if ((${#failed_builders[@]})); then
    echo "Retained builders for investigation:" >&2
    printf '  %s\n' "${failed_builders[@]}" >&2
  fi
  exit 1
fi

echo "All selected Docker CI builds passed."
