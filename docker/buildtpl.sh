#!/bin/sh
set -e
set -x

cd thirdPartyLibs_repo
python scripts/config-build.py -hc host-configs/environment.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-environment-release --installpath /home/geosx/thirdPartyLibs/install-environment-release
cd /home/geosx/thirdPartyLibs/build-environment-release
make hdf5 conduit axom silo chai raja fparser mathpresso pugixml metis parmetis superlu_dist hypre uncrustify petsc trilinos
cd ..
