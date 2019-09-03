#!/bin/sh
set -e
set -x

cd /home/geosx/GEOSX_repo
python scripts/config-build.py -hc host-configs/default.cmake -bt Release --buildpath /home/geosx/GEOSX/build-default-release --installpath /home/geosx/GEOSX/install-default-release -DGEOSX_TPL_ROOT_DIR:PATH=/home/geosx/thirdPartyLibs/install-default-release
cd /home/geosx/GEOSX/build-default-release
make
