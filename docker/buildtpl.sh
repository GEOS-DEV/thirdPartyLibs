#!/bin/sh
set -e
set -x

mkdir GEOSX
cd thirdPartyLibs_repo
python scripts/config-build.py -hc host-configs/default.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-default-release --installpath /home/geosx/thirdPartyLibs/install-default-release
cd /home/geosx/thirdPartyLibs/build-default-release
make 
cd thirdPartyLibs_repo/docker/GEOSX .
python scripts/config-build.py -hc host-configs/default.cmake -bt Release --buildpath /home/geosx/GEOSX/build-default-release --installpath /home/geosx/GEOSX/install-default-release -DGEOSX_TPL_ROOT_DIR:PATH=/home/geosx/thirdPartyLibs/install-default-release
cd /home/geosx/GEOSX/build-default-release
make
