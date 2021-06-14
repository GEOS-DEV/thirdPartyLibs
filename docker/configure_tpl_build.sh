#!/bin/sh

if [[ -z "${TPL_SRC_DIR}" ]]; then
  echo "Environment variable \"TPL_SRC_DIR\" is undefined."
  exit 1
fi

if [[ -z "${TPL_BUILD_DIR}" ]]; then
  echo "Environment variable \"TPL_BUILD_DIR\" is undefined."
  exit 1
fi

if [[ -z "${GEOSX_TPL_DIR}" ]]; then
  echo "Environment variable \"GEOSX_TPL_DIR\" is undefined."
  exit 1
fi

if [[ -z "${HOST_CONFIG}" ]]; then
  echo "Environment variable \"HOST_CONFIG\" is undefined."
  exit 1
fi

python ${TPL_SRC_DIR}/scripts/config-build.py \
       --hostconfig ${TPL_SRC_DIR}/${HOST_CONFIG} \
       --buildtype Release \
       --buildpath ${TPL_BUILD_DIR} \
       --installpath ${GEOSX_TPL_DIR} \
       -DNUM_PROC=$(nproc) \
       $*
# Note that since docker is not used for mac,\
# an other version of this build configuration exists
# in the .travis.yml part dedicated to osx
