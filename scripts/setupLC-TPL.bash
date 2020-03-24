#!/bin/bash

# Usage ./setupLC-TPL.bash pathToGeosxDirectory pathToInstallDirectory [extra rguments to config-build ]
shift
shift
python scripts/config-build.py -hc $1/host-configs/LLNL/toss_3_x86_64_ib-clang\@9.0.0.cmake -bt Release -ip $2/install-toss_3_x86_64_ib-clang\@9.0.0-release $@
python scripts/config-build.py -hc $1/host-configs/LLNL/toss_3_x86_64_ib-gcc\@8.1.0.cmake   -bt Release -ip $2/install-toss_3_x86_64_ib-gcc\@8.1.0-release   $@
python scripts/config-build.py -hc $1/host-configs/LLNL/toss_3_x86_64_ib-icc\@19.0.cmake    -bt Release -ip $2/install-toss_3_x86_64_ib-iccg\@19.0-release $@

python scripts/config-build.py -hc $1/host-configs/LLNL/lassen-clang\@upstream-NoMPI.cmake  -bt Release -ip $2/install-lassen-clang@upstream-NoMPI-release $@
python scripts/config-build.py -hc $1/host-configs/LLNL/lassen-clang\@upstream.cmake        -bt Release -ip $2/install-lassen-clang@upstream-release       $@
