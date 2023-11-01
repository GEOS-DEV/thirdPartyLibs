#!/bin/bash

## Builds the TPLs for a specific system and host config.
## Usage ./setupLC-TPL-uberenv-helper.bash pathToGeosxDirectory pathToInstallDirectory machine compiler commandToGetANode [extra arguments to config-build ]
#GEOSX_DIR=$1
GEOS_BRANCH=$1
INSTALL_DIR=$2
MACHINE=$3
COMPILER=$4
SPEC=$5
GET_A_NODE=$6

## Eat up the command line arguments so the rest can be forwarded to config-build.
shift
shift
shift
shift
shift

CONFIG=$MACHINE-$COMPILER
LOG_FILE=$CONFIG.log
HOST_CONFIG=$GEOSX_DIR/host-configs/LLNL/$CONFIG.cmake
INSTALL_DIR=$INSTALL_DIR/install-$CONFIG-release

#echo "Building the TPLs on $MACHINE for $HOST_CONFIG to be installed at $INSTALL_DIR. Progress will be written to $LOG_FILE."
echo "Building the TPLs on $MACHINE for $COMPILER to be installed at $INSTALL_DIR. Progress will be written to $LOG_FILE."

ssh $MACHINE -t "
. /etc/profile  &&
cd tempGEOS &&
$GET_A_NODE ./scripts/uberenv/uberenv.py --spec=$SPEC --prefix $INSTALL_DIR $@ &&
exit" > $LOG_FILE 2>&1

# ssh $MACHINE -t "
# . /etc/profile  &&
# cd $PWD &&
# module load cmake/3.23.1 &&
# python3 scripts/config-build.py -hc $HOST_CONFIG -bt Release -ip $INSTALL_DIR $@ &&
# cd build-$CONFIG-release &&
# $GET_A_NODE make &&
# exit" > $LOG_FILE 2>&1

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
