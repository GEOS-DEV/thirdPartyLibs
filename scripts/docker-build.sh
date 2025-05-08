#!/bin/bash
env

# We save memory for the docker context
echo .git > .dockerignore

# Get uberenv submodule
git submodule update --init scripts/uberenv


# This script will build an image from TPL_DOCKERFILE
# with (optional) DOCKER_COMPILER_BUILD_ARG build arguments.
# This image will be tagged with the DOCKER_REPOSITORY:DOCKER_TAG tag
# A specific host-config file can be defined through variable HOST_CONFIG.
# For the case of Total cluster only, DOCKER_ROOT_IMAGE is used to define docker base image.
# Where the TPL are installed in the docker can be specified by parameter INSTALL_DIR.
# These variables shall be defined by the "yaml derived classes" in a stage prior to `script` stage.
echo "Docker tag is ${DOCKER_REPOSITORY}:${DOCKER_TAG}"

INSTALL_DIR=${INSTALL_DIR_ROOT}/GEOS_TPL-${DOCKER_TAG}-${COMMIT:0:7}
echo "Installation directory is ${INSTALL_DIR}"

docker build --progress=plain ${DOCKER_COMPILER_BUILD_ARG} \
--build-arg HOST_CONFIG=${HOST_CONFIG} \
--build-arg DOCKER_ROOT_IMAGE=${DOCKER_ROOT_IMAGE} \
--build-arg INSTALL_DIR=${INSTALL_DIR} \
--build-arg SPEC="${SPEC}" \
--tag ${DOCKER_REPOSITORY}:${DOCKER_TAG} \
--file ${TPL_DOCKERFILE} \
--label "org.opencontainers.image.created=$(date --rfc-3339=seconds)" \
--label "org.opencontainers.image.source=https://github.com/GEOS-DEV/thirdPartyLibs" \
--label "org.opencontainers.image.revision=${COMMIT}" \
--label "org.opencontainers.image.title=Building environment for GEOS" \
.
