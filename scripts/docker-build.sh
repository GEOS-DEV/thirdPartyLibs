#!/bin/bash
set -e
env

# Keep the docker context to the sources the TPL build actually needs.
#
# In CI this is a fresh checkout and only .git matters. Run locally via
# scripts/reproduce_ci.sh, however, the working tree usually also holds build
# and install trees, which added ~27GB to every job's context, and stray
# host-configs left at the repo root by earlier local builds. Those last ones
# are not merely wasteful: the TPL Dockerfiles finish with
# `cp *.cmake /spack-generated.cmake`, so any root-level *.cmake beyond the one
# uberenv just generated makes cp treat the destination as a directory and the
# build fails after the whole TPL stack has been compiled. No tracked file at
# the repo root matches these patterns.
cat > .dockerignore <<'DOCKERIGNORE'
.git
build
build-*
install
install-*
*_tpls
.rocm-ci-local.*
*.cmake
*.log
__pycache__
DOCKERIGNORE

# Get uberenv submodule
git submodule update --init --force scripts/uberenv

# This script will build an image from TPL_DOCKERFILE.
# The new TPL Dockerfiles (docker/tpl-ubuntu.Dockerfile,
# docker/tpl-rockylinux.Dockerfile) layer on top of one of the geosx/<os>:<tag>
# base images produced by https://github.com/GEOS-DEV/docker_base_images. The
# matrix in .github/workflows/docker_build_tpls.yml selects which base image
# (DOCKER_BASE_IMAGE) and which spack toolchain (SPEC) to use.
#
# This image will be tagged with the DOCKER_REPOSITORY:DOCKER_TAG tag.
# A specific host-config file can be defined through variable HOST_CONFIG.
# Where the TPL are installed in the docker can be specified by parameter
# INSTALL_DIR.
echo "Docker tag is ${DOCKER_REPOSITORY}:${DOCKER_TAG}"

INSTALL_DIR=${INSTALL_DIR_ROOT}/GEOS_TPL-${DOCKER_TAG}-${COMMIT:0:7}
echo "Installation directory is ${INSTALL_DIR}"
echo "Docker base image is ${DOCKER_BASE_IMAGE}"

# Optional build-args are only forwarded when set, so the Dockerfiles can rely
# on `[ -z "${ARG}" ]` checks.
EXTRA_BUILD_ARGS=()
if [ -n "${GCC_VERSION}" ];   then EXTRA_BUILD_ARGS+=(--build-arg "GCC_VERSION=${GCC_VERSION}");     fi
if [ -n "${CLANG_VERSION}" ]; then EXTRA_BUILD_ARGS+=(--build-arg "CLANG_VERSION=${CLANG_VERSION}"); fi
# ROCm-only knobs, forwarded the same way (see docker/tpl-ubuntu-hip.Dockerfile).
if [ -n "${AMDGPU_TARGET}" ];    then EXTRA_BUILD_ARGS+=(--build-arg "AMDGPU_TARGET=${AMDGPU_TARGET}");       fi
if [ -n "${ROCM_VERSION}" ];     then EXTRA_BUILD_ARGS+=(--build-arg "ROCM_VERSION=${ROCM_VERSION}");         fi
if [ -n "${SPACK_BUILD_JOBS}" ]; then EXTRA_BUILD_ARGS+=(--build-arg "SPACK_BUILD_JOBS=${SPACK_BUILD_JOBS}"); fi

BUILDER_ARGS=()
if [ -n "${DOCKER_BUILDER:-}" ]; then BUILDER_ARGS+=(--builder "${DOCKER_BUILDER}"); fi
if [ "${DOCKER_LOAD:-0}" = 1 ]; then BUILDER_ARGS+=(--load); fi

docker build --progress=plain \
    "${BUILDER_ARGS[@]}" \
    --build-arg HOST_CONFIG=${HOST_CONFIG} \
    --build-arg DOCKER_BASE_IMAGE=${DOCKER_BASE_IMAGE} \
    --build-arg INSTALL_DIR=${INSTALL_DIR} \
    --build-arg SPEC="${SPEC}" \
    "${EXTRA_BUILD_ARGS[@]}" \
    --tag ${DOCKER_REPOSITORY}:${DOCKER_TAG} \
    --file ${TPL_DOCKERFILE} \
    --label "org.opencontainers.image.created=$(date --rfc-3339=seconds)" \
    --label "org.opencontainers.image.source=https://github.com/GEOS-DEV/thirdPartyLibs" \
    --label "org.opencontainers.image.revision=${COMMIT}" \
    --label "org.opencontainers.image.base.name=${DOCKER_BASE_IMAGE}" \
    --label "org.opencontainers.image.title=Building environment for GEOS" \
    .
