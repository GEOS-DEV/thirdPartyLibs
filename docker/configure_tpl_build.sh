#!/bin/sh

if [ -z "${SRC_DIR}" ]; then
  echo "Variable \"SRC_DIR\" is undefined."
  exit 1
fi

if [ -z "${BLD_DIR}" ]; then
  echo "Variable \"BLD_DIR\" is undefined."
  exit 1
fi

if [ -z "${GEOSX_TPL_DIR}" ]; then
  echo "Environment variable \"GEOSX_TPL_DIR\" is undefined."
  exit 1
fi

if [ -z "${HOST_CONFIG}" ]; then
  echo "Variable \"HOST_CONFIG\" is undefined."
  exit 1
fi

python3 ${TPL_SRC_DIR}/scripts/config-build.py \
        --hostconfig ${SRC_DIR}/${HOST_CONFIG} \
        --buildtype Release \
        --buildpath ${BLD_DIR} \
        --installpath ${GEOSX_TPL_DIR} \
        -DNUM_PROC=$(nproc) \
        $*
# Note that since docker is not used for mac,\
# an other version of this build configuration exists
# in the .travis.yml part dedicated to osx
