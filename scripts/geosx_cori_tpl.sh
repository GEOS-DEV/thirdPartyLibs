#
#Please add the following variables to bash_profile.ext
#

export CRAYPE_LINK_TYPE=dynamic
export HDF5_USE_FILE_LOCKING=FALSE
export XTPE_LINK_TYPE=dynamic

#Please set directory to GEOSX
export GEOSX_DIR=/global/homes/v/vargas45/Git-Repos/TEST_GEOSX/GEOSX

#Build TPLs
python config-build.py -hc ${GEOSX_DIR}/host-configs/cori-intel.cmake -bt Release && cd build-cori-intel-release && make -j && 

#Build GEOSX
cd ${GEOSX_DIR}/src/externalComponents && git submodule deinit PAMELA && git submodule deinit PVTPackage && cd ${GEOSX_DIR} &&
python scripts/config-build.py -hc host-configs/cori-intel.cmake -bt Release && cd build-cori-intel-release && make -j 


