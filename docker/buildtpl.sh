#!/bin/sh
set -e
set -x

cd thirdPartyLibs_repo
python scripts/config-build.py -hc host-configs/default.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-default-release --installpath /home/geosx/thirdPartyLibs/install-default-release
cd /home/geosx/thirdPartyLibs/build-default-release
make hdf5 conduit axom silo chai raja fparser mathpresso pugixml metis parmetis superlu_dist hypre uncrustify petsc trilinos
cd ..
