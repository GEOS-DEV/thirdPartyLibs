#!/bin/bash

## Builds the TPLs on all LC systems. Must be run from the top level TPL directory.
## EXAMPLE ./setupLC-TPL.bash /user/workspace/username/GEOS clang@14 Release 

# Default values
USER_NAME=$(whoami)
GEOS_DIR="/usr/workspace/${USER_NAME}/GEOS"
BUILD_TYPE="Release"
COMPILER="sysCompiler"
ORIGINAL_DIR=$(pwd)

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -geosPath)
            shift
            GEOS_DIR="$1"
            ;;
        -bt)
            shift
            BUILD_TYPE="$1"
            ;;
        -comp)
            shift
            COMPILER="$1"
            ;;
        -h)
            echo -e "Usage: 
            \n    -geosPath \"PATH_TO_GEOS_ROOT\" :: default /usr/WS1/<username>/GEOS
            \n    -bt \"BUILD_TYPE\"              :: default to Release (Release/Debug/RelWithDebInfo)
            \n    -comp \"COMPILER\"              :: default SYS_COMPILER \n"
            exit 1  
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# Get the machine name from uname -i and strip trailing integers
MACHINE=$(uname -n | sed 's/[0-9]*$//')
# Get the Bash version
BASH_VERSION=$(bash --version | grep -oE "[0-9]+\.[0-9]+" | head -n1)

GIT_REPO=$(git remote -v | awk '/origin.*\(push\)/ {print $2}')
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_COMMIT=$(git rev-parse --short HEAD)

INSTALL_DIR="$GEOS_DIR/tplInstall-${MACHINE,,}-${COMPILER,,}-${BUILD_TYPE,,}"
HOST_CONFIG=$GEOS_DIR/host-configs/LLNL/$MACHINE-$COMPILER.cmake

LOG_FILE="TPLBuild-$MACHINE-$COMPILER-${BUILD_TYPE,,}.log"
echo -e "\n---------------------------------------------------------------------------------------------------------------" > "$LOG_FILE"
echo -e "\nGit Info:\n    - Repository URL: $GIT_REPO\n    - Repository Branch: $GIT_BRANCH\n    - Commit: $GIT_COMMIT \n" >> "$LOG_FILE" 
echo -e "---------------------------------------------------------------------------------------------------------------\n" >> "$LOG_FILE"
echo "Script path and name: $(pwd)/${0#./}" >> "$LOG_FILE"
echo " " >> "$LOG_FILE"
echo "Bash:           $BASH_VERSION" >> "$LOG_FILE"
echo "User name:      $USER_NAME" >> "$LOG_FILE"
echo "GEOS_DIR:       $GEOS_DIR" >> "$LOG_FILE"
echo "Machine name:   $MACHINE" >> "$LOG_FILE"
echo "Compiler:       $COMPILER" >> "$LOG_FILE"
echo "Build type:     $BUILD_TYPE" >> "$LOG_FILE"
echo "Install path:   $INSTALL_DIR" >> "$LOG_FILE"
echo "host-config:    $HOST_CONFIG" >> "$LOG_FILE"
echo " " >> "$LOG_FILE"

# Compare the Bash version with 4
if (( $(echo "$BASH_VERSION < 4" | bc -l) )); then
    echo "Error: Required Bash >= 4, current bash version is ${BASH_VERSION}." >> "$LOG_FILE" 
    echo " " >> "$LOG_FILE"
    exit 1
fi

if [ ! -f "$HOST_CONFIG" ]; then
    echo -e "Error: Host config file ${HOST_CONFIG} does not exist. \n    Please correct this and try again." >> "$LOG_FILE" 
    echo " " >> "$LOG_FILE"
    exit 1
fi

## Trap the interupt signal and kill all children.
trap 'killall' INT

killall() {
    trap '' INT TERM     # ignore INT and TERM while shutting down
    echo "**** Shutting down. Killing chid processes ****"     # added double quotes
    kill -TERM 0         # fixed order, send TERM not INT
    wait
    echo DONE
}

if [ -n "$(find . -maxdepth 1 -type d -name 'build-*' -print -quit)" ]; then
    echo "Existing build directories have been found, these are being deleted. " >> "$LOG_FILE"
    # Check if the toBeDeleted directory exists
    if [ -d toBeDeleted ]; then
        # If the directory exists, delete it
        echo "For some reason the directory toBeDeleted already existed, so this" >> "$LOG_FILE"
        echo "    directory is being deleted." >> "$LOG_FILE"
        rm -rf toBeDeleted 
    fi

    mkdir toBeDeleted
    echo "Created a toBeDeleted directory. " >> "$LOG_FILE"

    mv build-* toBeDeleted    
    echo "Moved build directories to the toBeDeleted directory. " >> "$LOG_FILE"

    rm -rf toBeDeleted 
    echo "Deleted the toBeDeleted directory. " >> "$LOG_FILE"
fi

echo -e "Building all LC TPLs from $GEOS_DIR \n    to be installed at $INSTALL_DIR \n" >> "$LOG_FILE"
if [ -d "$INSTALL_DIR" ]; then
    echo -e "$INSTALL_DIR exists, \n   deleting its contents.\n" >> "$LOG_FILE"
    rm -r "$INSTALL_DIR"
else
    echo -e "$INSTALL_DIR does not exist, \n    creating it and giving rx permisions.\n" >> "$LOG_FILE"
fi
mkdir $INSTALL_DIR
# chmod -R +rx $INSTALL_DIR

echo -e "---------------------------------------------------------------------------------------------------------------\n" >> "$LOG_FILE"
module -T load cmake >> "$LOG_FILE" 2>&1
echo " " >> "$LOG_FILE"

python3 scripts/config-build.py -hc $HOST_CONFIG -bt $BUILD_TYPE -ip $INSTALL_DIR | tee -a "$LOG_FILE" 2>&1 
cd build-$MACHINE-$COMPILER-${BUILD_TYPE,,} 
echo "changed to build-$MACHINE-$COMPILER-${BUILD_TYPE,,}  directory " | tee -a "$LOG_FILE" 2>&1
srun -N1 -t60 -ppdebug make | tee -a "$LOG_FILE" 2>&1
# echo " $GET_A_NODE"
# $GET_A_NODE make |

# if [ "${MACHINE,,}" = "quartz" ]; then
#     echo " ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE \"srun -N 1 -t 90 -n 1\" " >> "$LOG_FILE"
#     ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE 'srun -N 1 -t 90 -n 1' #| tee -a "$LOG_FILE"
# elif [ "${MACHINE,,}" = "lassen" ]; then
#     echo " ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE \"lalloc 1 -qpdebug\" " >> "$LOG_FILE"
#     ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE 'lalloc 1 -qpdebug' #| tee -a "$LOG_FILE"  
# else    
#     echo "MACHINE: ${MACHINE,,} is currently not supported. "
# fi

# # wait
# # echo "Complete" | tee -a "$LOG_FILE"
# echo " ${MACHINE,,}-${BUILD_TYPE,,}"