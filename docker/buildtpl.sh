#!/bin/sh
set -e
set -x

cd thirdPartyLibs
python scripts/config-build.py -hc host-configs/default.cmake -bt Release -DNUM_PROC:STRING=2
cd build-default-release
make hdf5 conduit axom silo chai raja fparser mathpresso pugixml metis parmetis superlu_dist hypre uncrustify
cd ..
git submodule deinit .
rm -rf build-default-release
