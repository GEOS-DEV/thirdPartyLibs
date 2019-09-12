#!/bin/sh
set -e
set -x

function or_die () {
    "$@"
    local status=$?
    if [[ $status != 0 ]] ; then
        echo ERROR $status command: $@
        exit $status
    fi
}

cd /home/geosx/GEOSX
mkdir build
cd build
or_die cmake \
           -DCMAKE_C_COMPILER=${CC} -DCMAKE_CXX_COMPILER=${CXX} -DCMAKE_Fortran_COMPILER=${FC} \
           -DENABLE_MPI=ON -DMPI_C_COMPILER=${MPICC} -DMPI_CXX_COMPILER=${MPICXX} -DMPI_Fortran_COMPILER=${MPIFC} -DMPIEXEC=${MPIEXEC} -DMPIEXEC_EXECUTABLE=${MPIEXEC} \
           -DGEOSX_TPL_DIR=/home/geosx/thirdPartyLibs/install-default-release \
           -DENABLE_SPHINX=OFF \
           -DCMAKE_BUILD_TYPE=Release \
           ../src
or_die make -j 1 VERBOSE=1

exit 0