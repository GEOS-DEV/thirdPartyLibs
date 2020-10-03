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

# Our travis build only offers 8 Gb of RAM and 
# trilinos requires a lot of memory to compile.
# A solution is to limit the number of concurrent jobs for trilinos.
python ${TPL_SRC_DIR}/scripts/config-build.py \
       --hostconfig ${TPL_SRC_DIR}/host-configs/environment.cmake \
       --buildtype Release \
       --buildpath ${TPL_BUILD_DIR} \
       --installpath ${GEOSX_TPL_DIR} \
       -DTRILINOS_NUM_PROC=$(nproc) \
       -DNUM_PROC=$(nproc) \
       $*
# Note that since docker is not used for mac,\
# an other version of this build configuration exists
# in the .travis.yml part dedicated to osx
