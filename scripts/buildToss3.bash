#!/bin/bash
python scripts/config-build.py -hc ../GEOSX/host-configs/toss_3_x86_64_ib-clang\@6.0.0.cmake -bt Release -ip /usr/gapps/GEOS/geosx/thirdPartyLibs/install-toss_3_x86_64_ib-clang\@6.0.0-release -DENABLE_UNCRUSTIFY:BOOL=OFF
python scripts/config-build.py -hc ../GEOSX/host-configs/toss_3_x86_64_ib-clang\@8.0.1.cmake -bt Release -ip /usr/gapps/GEOS/geosx/thirdPartyLibs/install-toss_3_x86_64_ib-clang\@8.0.1-release -DENABLE_UNCRUSTIFY:BOOL=OFF
python scripts/config-build.py -hc ../GEOSX/host-configs/toss_3_x86_64_ib-gcc\@8.1.0.cmake -bt Release -ip /usr/gapps/GEOS/geosx/thirdPartyLibs/install-toss_3_x86_64_ib-gcc\@8.1.0-release -DENABLE_UNCRUSTIFY:BOOL=OFF
