#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run-rocm-ci-local.sh [options]

Launch the ROCm CI Docker build locally, using the same Dockerfile and
roughly the same build arguments as the GitHub Actions ROCm job.

Options:
  --tag TAG                 Docker tag to use. Default: local
  --repository REPO         Docker repository name.
                            Default: geosx/ubuntu24.04-amdclang19.0.0-rocm6.4.3
  --install-dir-root DIR    Install root inside the image. Default: /opt/GEOS
  --docker-root-image IMG   Base image. Default: rocm/dev-ubuntu-24.04:6.4.3
  --amdgpu-target TARGET    AMD GPU target passed into the build. Default: gfx942
  --spack-build-jobs N      Pass SPACK_BUILD_JOBS to the Docker build. Default: 2
  --target STAGE            Stop the build at a specific Docker stage.
  --ca-bundle PATH          Inject this CA bundle into the Docker build.
  --no-ca-inject            Disable CA injection even if a host CA bundle is found.
  --no-cache                Build with --no-cache.
  --dry-run                 Print the docker build command and exit.
  -h, --help                Show this help.
EOF
}

repo_root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
cd "$repo_root"

docker_repository="geosx/ubuntu24.04-amdclang19.0.0-rocm6.4.3"
docker_tag="local"
install_dir_root="/opt/GEOS"
docker_root_image="rocm/dev-ubuntu-24.04:6.4.3"
amdgpu_target="gfx942"
spack_build_jobs="2"
docker_target=""
ca_bundle=""
inject_ca="auto"
no_cache=0
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      docker_tag="$2"
      shift 2
      ;;
    --repository)
      docker_repository="$2"
      shift 2
      ;;
    --install-dir-root)
      install_dir_root="$2"
      shift 2
      ;;
    --docker-root-image)
      docker_root_image="$2"
      shift 2
      ;;
    --amdgpu-target)
      amdgpu_target="$2"
      shift 2
      ;;
    --spack-build-jobs)
      spack_build_jobs="$2"
      shift 2
      ;;
    --target)
      docker_target="$2"
      shift 2
      ;;
    --ca-bundle)
      ca_bundle="$2"
      inject_ca="yes"
      shift 2
      ;;
    --no-ca-inject)
      inject_ca="no"
      shift
      ;;
    --no-cache)
      no_cache=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$inject_ca" == "auto" ]]; then
  for candidate in \
    /etc/pki/tls/certs/ca-bundle.crt \
    /etc/ssl/certs/ca-certificates.crt
  do
    if [[ -f "$candidate" ]]; then
      ca_bundle="$candidate"
      inject_ca="yes"
      break
    fi
  done
fi

tmp_dir="$(mktemp -d "$repo_root/.rocm-ci-local.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

tmp_dockerfile="$tmp_dir/tpl-ubuntu-hip.local.Dockerfile"
cp docker/tpl-ubuntu-hip.Dockerfile "$tmp_dockerfile"

if [[ "$inject_ca" == "yes" ]]; then
  if [[ -z "$ca_bundle" || ! -f "$ca_bundle" ]]; then
    echo "CA injection requested but bundle was not found: ${ca_bundle:-<empty>}" >&2
    exit 1
  fi

  cp "$ca_bundle" "$tmp_dir/host-ca.crt"
  python3 - "$tmp_dockerfile" "$(basename "$tmp_dir")/host-ca.crt" <<'PY'
import pathlib
import sys

dockerfile = pathlib.Path(sys.argv[1])
bundle_rel = sys.argv[2]
text = dockerfile.read_text()
needle = "RUN ln -fs /usr/share/zoneinfo/America/Los_Angeles /etc/localtime && \\\n    apt-get update"
replacement = (
    f"COPY {bundle_rel} /usr/local/share/ca-certificates/host-ca.crt\n"
    "RUN update-ca-certificates\n\n"
    + needle
)
if needle not in text:
    raise SystemExit("Could not find apt-get hook for CA injection")
dockerfile.write_text(text.replace(needle, replacement, 1))
PY
fi

if [[ ! -f scripts/uberenv/uberenv.py ]]; then
  if [[ $dry_run -eq 1 ]]; then
    echo "uberenv submodule missing; dry-run skipping submodule update"
  else
    echo "Updating uberenv submodule"
    git submodule update --init scripts/uberenv
  fi
fi

commit_sha="$(git rev-parse HEAD)"
install_dir="${install_dir_root}/GEOS_TPL-${docker_tag}-${commit_sha:0:7}"

docker_args=(
  build
  --progress=plain
  --build-context "uberenv=${repo_root}/scripts/uberenv"
  --build-arg "DOCKER_ROOT_IMAGE=${docker_root_image}"
  --build-arg "AMDGPU_TARGET=${amdgpu_target}"
  --build-arg "INSTALL_DIR=${install_dir}"
  --tag "${docker_repository}:${docker_tag}"
  --file "$tmp_dockerfile"
  --label "org.opencontainers.image.created=$(date --rfc-3339=seconds)"
  --label "org.opencontainers.image.source=https://github.com/GEOS-DEV/thirdPartyLibs"
  --label "org.opencontainers.image.revision=${commit_sha}"
  --label "org.opencontainers.image.title=Building environment for GEOS"
)

if [[ -n "$spack_build_jobs" ]]; then
  docker_args+=(--build-arg "SPACK_BUILD_JOBS=${spack_build_jobs}")
fi

if [[ -n "$docker_target" ]]; then
  docker_args+=(--target "${docker_target}")
fi

if [[ $no_cache -eq 1 ]]; then
  docker_args+=(--no-cache)
fi

docker_args+=("$repo_root")

echo "Repository: ${docker_repository}"
echo "Tag: ${docker_tag}"
echo "Install dir: ${install_dir}"
echo "Dockerfile: ${tmp_dockerfile}"
echo "AMDGPU target: ${amdgpu_target}"
echo "Spack build jobs: ${spack_build_jobs}"
if [[ -n "$docker_target" ]]; then
  echo "Build target: ${docker_target}"
else
  echo "Build target: final image"
fi
if [[ "$inject_ca" == "yes" ]]; then
  echo "Injected CA bundle: ${ca_bundle}"
else
  echo "Injected CA bundle: none"
fi

printf 'Running: docker'
for arg in "${docker_args[@]}"; do
  printf ' %q' "$arg"
done
printf '\n'

if [[ $dry_run -eq 1 ]]; then
  exit 0
fi

DOCKER_BUILDKIT=1 docker "${docker_args[@]}"
