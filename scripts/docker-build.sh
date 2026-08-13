#!/bin/bash
# Workflows have historically invoked this script with `bash -x`; disable xtrace
# before handling build metadata so unrelated environment values are not leaked.
set +x
set -eo pipefail

: "${DOCKER_REPOSITORY:?DOCKER_REPOSITORY must be set}"
: "${DOCKER_TAG:?DOCKER_TAG must be set}"
: "${INSTALL_DIR_ROOT:?INSTALL_DIR_ROOT must be set}"
: "${COMMIT:?COMMIT must be set}"
: "${DOCKER_BASE_IMAGE:?DOCKER_BASE_IMAGE must be set}"
: "${HOST_CONFIG:?HOST_CONFIG must be set}"
: "${SPEC:?SPEC must be set}"
: "${TPL_DOCKERFILE:?TPL_DOCKERFILE must be set}"

# We save memory for the docker context
echo .git > .dockerignore

# Get uberenv submodule
git submodule update --init scripts/uberenv


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
if [ -n "${GCC_VERSION:-}" ];   then EXTRA_BUILD_ARGS+=(--build-arg "GCC_VERSION=${GCC_VERSION}");     fi
if [ -n "${CLANG_VERSION:-}" ]; then EXTRA_BUILD_ARGS+=(--build-arg "CLANG_VERSION=${CLANG_VERSION}"); fi

# Ubuntu MPI selections are a closed tuple. Prefixes and launchers are derived,
# never accepted from the caller, so image metadata cannot disagree with the
# provider that was compiled into the image.
HBV4_DOCKER_ARGS=()
if [[ "${TPL_DOCKERFILE}" == *tpl-ubuntu.Dockerfile ]]; then
    MPI_PROVIDER=${MPI_PROVIDER:-openmpi}
    SPACK_ENV_FILE=${SPACK_ENV_FILE:-docker/ubuntu-spack.yaml}
    HBV4_BUILD=${HBV4_BUILD:-0}
    SOURCE_SHA=${SOURCE_SHA:-}

    case "${MPI_PROVIDER}:${SPACK_ENV_FILE}:${HBV4_BUILD}" in
        openmpi:docker/ubuntu-spack.yaml:0)
            MPI_PREFIX=/opt/openmpi/5.0.10
            MPIEXEC_PATH=${MPI_PREFIX}/bin/mpirun
            FINAL_IMAGE_VARIANT=portable
            ;;
        openmpi:docker/ubuntu-hbv4-openmpi-spack.yaml:1)
            MPI_PREFIX=/opt/openmpi/5.0.10
            MPIEXEC_PATH=${MPI_PREFIX}/bin/mpirun
            FINAL_IMAGE_VARIANT=hbv4
            ;;
        mpich:docker/ubuntu-hbv4-mpich-spack.yaml:1)
            MPI_PREFIX=/opt/mpich/5.0.1
            MPIEXEC_PATH=${MPI_PREFIX}/bin/mpiexec
            FINAL_IMAGE_VARIANT=hbv4
            ;;
        *)
            echo "ERROR: invalid MPI_PROVIDER/SPACK_ENV_FILE/HBV4_BUILD selection" >&2
            exit 1
            ;;
    esac

    if [ "${HBV4_BUILD}" = 1 ] && ! [[ "${SOURCE_SHA}" =~ ^[0-9a-f]{40}$ ]]; then
        echo "ERROR: SOURCE_SHA must be exactly 40 lowercase hexadecimal characters for HBv4 builds" >&2
        exit 1
    fi
    if [ "${HBV4_BUILD}" = 1 ] && ! [[ "${DOCKER_BASE_IMAGE}" =~ ^.+@sha256:[0-9a-f]{64}$ ]]; then
        echo "ERROR: HBv4 DOCKER_BASE_IMAGE must be pinned by sha256 digest" >&2
        exit 1
    fi

    EXTRA_BUILD_ARGS+=(
        --build-arg "MPI_PROVIDER=${MPI_PROVIDER}"
        --build-arg "MPI_PREFIX=${MPI_PREFIX}"
        --build-arg "MPIEXEC_PATH=${MPIEXEC_PATH}"
        --build-arg "SPACK_ENV_FILE=${SPACK_ENV_FILE}"
        --build-arg "HBV4_BUILD=${HBV4_BUILD}"
        --build-arg "SOURCE_SHA=${SOURCE_SHA}"
        --build-arg "FINAL_IMAGE_VARIANT=${FINAL_IMAGE_VARIANT}"
    )
    if [ "${HBV4_BUILD}" = 1 ]; then
        HBV4_DOCKER_ARGS=(--pull --no-cache)
    fi
fi

BUILDER_ARGS=()
if [ -n "${DOCKER_BUILDER:-}" ]; then BUILDER_ARGS+=(--builder "${DOCKER_BUILDER}"); fi
if [ "${DOCKER_LOAD:-0}" = 1 ]; then BUILDER_ARGS+=(--load); fi

docker build --progress=plain \
    "${BUILDER_ARGS[@]}" \
    "${HBV4_DOCKER_ARGS[@]}" \
    --build-arg "HOST_CONFIG=${HOST_CONFIG}" \
    --build-arg "DOCKER_BASE_IMAGE=${DOCKER_BASE_IMAGE}" \
    --build-arg "INSTALL_DIR=${INSTALL_DIR}" \
    --build-arg SPEC="${SPEC}" \
    "${EXTRA_BUILD_ARGS[@]}" \
    --tag "${DOCKER_REPOSITORY}:${DOCKER_TAG}" \
    --file "${TPL_DOCKERFILE}" \
    --label "org.opencontainers.image.created=$(date --rfc-3339=seconds)" \
    --label "org.opencontainers.image.source=https://github.com/GEOS-DEV/thirdPartyLibs" \
    --label "org.opencontainers.image.revision=${SOURCE_SHA:-${COMMIT}}" \
    --label "org.opencontainers.image.base.name=${DOCKER_BASE_IMAGE}" \
    --label "org.opencontainers.image.title=Building environment for GEOS" \
    .
