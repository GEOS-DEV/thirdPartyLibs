#!/bin/bash

## Builds the TPLs for a specific system and host config.
## Usage ./setupLC-TPL-helper.bash pathToGeosxDirectory pathToInstallDirectory machine compiler commandToGetANode [extra arguments to config-build ]
GEOS_DIR=$1
INSTALL_DIR=$2
MACHINE=$3
COMPILER=$4
GET_A_NODE=$5

if   [[ ${MACHINE} == "ruby"   ||\
        ${MACHINE} == "dane" ]]; then
    CMAKE_VERSION=cmake/3.26.3 
elif [[ ${MACHINE} == "lassen" ]]; then
    CMAKE_VERSION=cmake/3.29.2 
fi

## Eat up the command line arguments so the rest can be forwarded to config-build.
shift
shift
shift
shift
shift

CONFIG=$MACHINE-$COMPILER
LOG_FILE=$CONFIG.log
HOST_CONFIG=$GEOS_DIR/host-configs/LLNL/$CONFIG.cmake
INSTALL_DIR=$INSTALL_DIR/install-$CONFIG-release

echo "Building the TPLs on $MACHINE for $HOST_CONFIG to be installed at $INSTALL_DIR. Progress will be written to $LOG_FILE."

ssh $MACHINE -t "
. /etc/profile  &&
cd $PWD &&
module load $CMAKE_VERSION
python3 scripts/config-build.py -hc $HOST_CONFIG -bt Release -ip $INSTALL_DIR $@ &&
cd build-$CONFIG-release &&
$GET_A_NODE make &&
exit" > $LOG_FILE 2>&1

## Check the last three lines of the log file. A BLT smoke test should be the last
## thing built and should show up on one of the final lines.
tail -3 $LOG_FILE | grep -E "\[100%\] Built target blt_.*_smoke" > /dev/null
if [ $? -eq 0 ]; then
    chmod g+rx -R $INSTALL_DIR
    chgrp GEOS -R $INSTALL_DIR
    echo "Build of $HOST_CONFIG completed successfully."
    exit 0
else
    echo "Build of $HOST_CONFIG seemed to fail, check $LOG_FILE."
    exit 1
fi
