#!/bin/bash
env

# We save memory for the docker context
echo .git > .dockerignore
# This script will build and push a DOCKER_REPOSITORY:DOCKER_TAG image build from DOCKERFILE
# with (optional) DOCKER_COMPILER_BUILD_ARG build arguments.
# A specific host-config file can be defined through variable HOST_CONFIG.
# For the case of Total cluster only, DOCKER_ROOT_IMAGE is used to define docker base image.
# Where the TPL are installed in the docker can be specified by parameter INSTALL_DIR.
# Unlike DOCKER_TAG, these variables shall be defined by the "yaml derived classes" in a stage prior to `script` stage.
DOCKER_TAG=${PULL_REQUEST_NUMBER}-${BUILD_NUMBER}
echo "${DOCKER_USERNAME}"
echo "${DOCKER_REPOSITORY}:${DOCKER_TAG}"
docker build ${DOCKER_COMPILER_BUILD_ARG} \
--build-arg HOST_CONFIG=${HOST_CONFIG:-host-configs/environment.cmake} \
--build-arg DOCKER_ROOT_IMAGE=${DOCKER_ROOT_IMAGE:-undefined} \
--build-arg INSTALL_DIR=${INSTALL_DIR:-/opt/GEOSX_TPL} \
--tag ${DOCKER_REPOSITORY}:${DOCKER_TAG} \
--file ${DOCKERFILE} \
--label "org.opencontainers.image.created=$(date --rfc-3339=seconds)" \
--label "org.opencontainers.image.source=https://github.com/GEOSX/thirdPartyLibs" \
--label "org.opencontainers.image.revision=${COMMIT}" \
--label "org.opencontainers.image.title=Building environment for GEOSX" \
.

docker push ${DOCKER_REPOSITORY}:${DOCKER_TAG}
