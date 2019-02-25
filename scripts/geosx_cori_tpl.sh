!/bin/bash
#
#Please add the following variables to bash_profile.ext
#

module load cmake/3.11.4

export CRAYPE_LINK_TYPE=dynamic
export HDF5_USE_FILE_LOCKING=FALSE
export XTPE_LINK_TYPE=dynamic

#Please set directory to GEOSX
export GEOSX_DIR=../GEOSX

#Build TPLs
python scripts/config-build.py -hc ${GEOSX_DIR}/host-configs/cori-intel.cmake -bt Release && cd build-cori-intel-release && make 

#Build GEOSX
# cd ${GEOSX_DIR}/src/externalComponents && git submodule deinit PAMELA && git submodule deinit PVTPackage && cd ${GEOSX_DIR} &&
# python scripts/config-build.py -hc host-configs/cori-intel.cmake -bt Release && cd build-cori-intel-release && make -j 