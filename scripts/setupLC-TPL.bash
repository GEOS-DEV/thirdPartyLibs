#!/bin/bash
python scripts/config-build.py -hc ../GEOSX/host-configs/LLNL/toss_3_x86_64_ib-clang\@9.0.0.cmake -bt Release -ip /usr/gapps/GEOSX/thirdPartyLibs/2019-11-19/install-toss_3_x86_64_ib-clang\@9.0.0-release -DENABLE_UNCRUSTIFY:BOOL=OFF
python scripts/config-build.py -hc ../GEOSX/host-configs/LLNL/toss_3_x86_64_ib-gcc\@8.1.0.cmake   -bt Release -ip /usr/gapps/GEOSX/thirdPartyLibs/2019-11-19/install-toss_3_x86_64_ib-gcc\@8.1.0-release   -DENABLE_UNCRUSTIFY:BOOL=OFF
python scripts/config-build.py -hc ../GEOSX/host-configs/LLNL/toss_3_x86_64_ib-icc\@19.0.cmake    -bt Release -ip /usr/gapps/GEOSX/thirdPartyLibs/2019-11-19/install-toss_3_x86_64_ib-iccg\@19.0-release -DENABLE_UNCRUSTIFY:BOOL=OFF

python scripts/config-build.py -hc ../GEOSX/host-configs/LLNL/lassen-clang\@upstream-NoMPI.cmake -bt Release -ip /usr/gapps/GEOSX/thirdPartyLibs/2019-11-19/install-lassen-clang@upstream-NoMPI-release -DENABLE_UNCRUSTIFY:BOOL=OFF
python scripts/config-build.py -hc ../GEOSX/host-configs/LLNL/lassen-clang\@upstream.cmake       -bt Release -ip /usr/gapps/GEOSX/thirdPartyLibs/2019-11-19/install-lassen-clang@upstream-release       -DENABLE_UNCRUSTIFY:BOOL=OFF
