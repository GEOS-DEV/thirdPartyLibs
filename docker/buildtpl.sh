#!/bin/sh
set -e
set -x

python scripts/config-build.py -hc host-configs/environment.cmake -bt Release -DNUM_PROC:STRING=2 --buildpath /home/geosx/thirdPartyLibs/build-environment-release --installpath /home/geosx/thirdPartyLibs/install-environment-release
cd /home/geosx/thirdPartyLibs/build-environment-release
make 
