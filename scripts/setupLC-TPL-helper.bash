#!/bin/bash

## Builds the TPLs for a specific system and host config.
## Usage ./setupLC-TPL-helper.bash pathToGeosxDirectory pathToInstallDirectory machine compiler commandToGetANode [extra arguments to config-build ]
GEOSX_DIR=$1
INSTALL_DIR=$2
MACHINE=$3
COMPILER=$4
BUILD_TYPE=$5
GET_A_NODE=$6

## Eat up the command line arguments so the rest can be forwarded to config-build.
shift
shift
shift
shift
shift

CONFIG=$MACHINE-$COMPILER
HOST_CONFIG=$GEOSX_DIR/host-configs/LLNL/$CONFIG.cmake
INSTALL_DIR=$INSTALL_DIR/install-$CONFIG-${BUILD_TYPE,,}
LOG_FILE="TPLBuild-$MACHINE-$COMPILER-${BUILD_TYPE,,}.log"

echo "Building the TPLs on $MACHINE for $HOST_CONFIG to be installed at $INSTALL_DIR." 
echo "Progress will be written to $LOG_FILE."

module load cmake/3.23.1 #2&>1 | tee -a "$LOG_FILE"
echo " loaded cmake " >> "$LOG_FILE"
python3 scripts/config-build.py -hc $HOST_CONFIG -bt $BUILD_TYPE -ip $INSTALL_DIR 2&>1 | tee -a "$LOG_FILE"
echo " ran config-build.py " >> "$LOG_FILE"
cd build-$CONFIG-${BUILD_TYPE,,} && echo " changed to build-$CONFIG-${BUILD_TYPE,,} directory " >> "$LOG_FILE"
echo " changed to build-$CONFIG-${BUILD_TYPE,,} directory " >> "$LOG_FILE"
echo " $GET_A_NODE"
$GET_A_NODE make |

## Check the last three lines of the log file. A BLT smoke test should be the last
## thing built and should show up on one of the final lines.
tail -3 $LOG_FILE | grep -E "\[100%\] Built target blt_.*_smoke" > /dev/null
if [ $? -eq 0 ]; then
    chmod g+rx -R $INSTALL_DIR
    echo "Build of $HOST_CONFIG completed successfully."
    exit 0
else
    echo "Build of $HOST_CONFIG seemed to fail, check $LOG_FILE."
    exit 1
fi
