#!/bin/bash

## Builds the TPLs for a specific system and host config.
## Usage ./setupLC-TPL-uberenv-helper.bash pathToInstallDirectory machine compiler spackSpecToBuild commandToGetANode
INSTALL_DIR=$1
MACHINE=$2
COMPILER=$3
SPEC=\"${4}\"
GET_A_NODE=$5

## Eat up the command line arguments so the rest can be forwarded to config-build.
shift
shift
shift
shift
shift

CONFIG=$MACHINE-$COMPILER
LOG_FILE=$CONFIG.log

echo "Building the TPLs on $MACHINE for $COMPILER to be installed at $INSTALL_DIR. Progress will be written to $LOG_FILE."

ssh $MACHINE -t "
. /etc/profile  &&
cd $PWD/tempGEOS &&
$GET_A_NODE ./scripts/uberenv/uberenv.py --spec ${SPEC} --prefix ${INSTALL_DIR}/${CONFIG}_tpls --spack-env-name ${CONFIG}_env &&
exit" > $LOG_FILE 2>&1

## Check the last ten lines of the log file.
## A successful install should show up on one of the final lines.
tail -10 $LOG_FILE | grep -E "Successfully installed geos" > /dev/null
if [ $? -eq 0 ]; then
    chmod g+rx -R $INSTALL_DIR
    chgrp GEOS -R $INSTALL_DIR
    echo "Build of ${CONFIG} completed successfully."
    exit 0
else
    echo "Build of ${CONFIG} seemed to fail, check $LOG_FILE."
    exit 1
fi
