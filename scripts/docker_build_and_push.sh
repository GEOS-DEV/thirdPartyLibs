#!/bin/bash
env

if [ "$OS" == "ubuntu-22.04" ]
then
  # We save memory for the docker context
  echo .git > .dockerignore
  # This script will build and push a DOCKER_REPOSITORY:DOCKER_TAG image build from DOCKERFILE
  # with (optional) DOCKER_COMPILER_BUILD_ARG build arguments.
  # A specific host-config file can be defined through variable HOST_CONFIG.
  # For the case of Total cluster only, DOCKER_ROOT_IMAGE is used to define docker base image.
  # Where the TPL are installed in the docker can be specified by parameter INSTALL_DIR.
  # Unlike DOCKER_TAG, these variables shall be defined by the "yaml derived classes" in a stage prior to `script` stage.
  DOCKER_TAG=${PULL_REQUEST_NUMBER}-${BUILD_NUMBER}
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

elif [ "$OS" == "macos-12" ]
then
  BREW_OPENMPI_VERSION=4.1.1
  BREW_OPENMPI_TAP=${USER}/local-open-mpi
  brew tap-new ${BREW_OPENMPI_TAP}
  brew extract --version=${BREW_OPENMPI_VERSION} open-mpi ${BREW_OPENMPI_TAP}
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_MAKE_JOBS=$(nproc) brew install \
    ${BREW_OPENMPI_TAP}/open-mpi@${BREW_OPENMPI_VERSION} \
    git-lfs
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_MAKE_JOBS=$(nproc) brew reinstall --verbose \
    gcc@11
  #ls -R /usr/bin
  echo ?????????????????????
  brew info gcc@11
  which gfortran
  which gcc
  whereis gcc
  whereis gfortran
  gfortran --version
  echo ?????????????????????
  git lfs install
  git lfs pull
  GEOSX_DIR=/usr/local/GEOSX && sudo mkdir -p -m a=rwx ${GEOSX_DIR}
  GEOSX_TPL_DIR=${GEOSX_DIR}/GEOSX_TPL
  python3 scripts/config-build.py \
    -hc ${BUILD_DIR}/host-configs/darwin-clang.cmake \
    -bt Release \
    -ip ${GEOSX_TPL_DIR} \
    -DNUM_PROC=$(nproc) \
    -DGEOSXTPL_ENABLE_DOXYGEN:BOOL=OFF \
    -DENABLE_VTK:BOOL=OFF \
    -DENABLE_TRILINOS:BOOL=OFF
  cd build-darwin-clang-release
  make

  # TODO: Update Google Cloud authentication process
  # python3 -m pip install google-cloud-storage 
  # cd ${BUILD_DIR}
  # openssl aes-256-cbc -K $encrypted_5ac030ea614b_key -iv $encrypted_5ac030ea614b_iv -in geosx-key.json.enc -out geosx-key.json -d
  # python3 macosx_TPL_mngt.py ${GEOSX_TPL_DIR} geosx-key.json ${BREW_HASH}

else
  echo "os $OS not found"
  exit 1
fi
