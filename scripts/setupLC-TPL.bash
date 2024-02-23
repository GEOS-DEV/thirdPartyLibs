#!/bin/bash

# Get the Bash version
bash_version=$(bash --version | grep -oE "[0-9]+\.[0-9]+" | head -n1)

# Compare the Bash version with 4
if (( $(echo "$bash_version >= 4" | bc -l) )); then
    echo "Bash version ${bash_version}."
    echo " "
else
    echo "Error: Required Bash >= 4, current bash version is ${bash_version}."
    echo " "
    exit 1
fi

git_repo=$(git remote -v | awk '/origin.*\(push\)/ {print $2}')
git_branch=$(git rev-parse --abbrev-ref HEAD)
git_commit=$(git rev-parse --short HEAD)

## Builds the TPLs on all LC systems. Must be run from the top level TPL directory.
## Usage ./setupLC-TPL.bash pathToGeosxDirectory machine compiler buildtype [extra arguments to config-build ]
## EXAMPLE ./setupLC-TPL.bash /user/workspace/username/GEOS quartz clang@14 Release 
GEOS_DIR=$1
INSTALL_DIR=$GEOS_DIR
MACHINE=$2
COMPILER=$3
BUILD_TYPE=$4

LOG_FILE="TPLBuild-$MACHINE-$COMPILER-${BUILD_TYPE,,}.log"
echo -e "\nGit Info:\n    - Repository URL: $git_repo\n    - Repository Branch: $git_branch\n    - Commit: $git_commit" > "$LOG_FILE" 
echo -e "-------------------------------------------------------------------------------\n" >> "$LOG_FILE"
echo "Script path and name: $(pwd)/$0" >> "$LOG_FILE"
echo ""
echo "Bash version ${bash_version}." >> $LOG_FILE
echo " " >> $LOG_FILE
echo -e "Script run using command:\n    $0 $*" >> $LOG_FILE

## Eat up the command line arguments so the rest can be forwarded to setupLC-TPL-helper.
shift
shift

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

echo "Building all LC TPLs from $GEOS_DIR to be installed at $INSTALL_DIR" | tee -a "$LOG_FILE"
chmod -R g+rx $INSTALL_DIR
if [ "${MACHINE,,}" = "quartz" ]; then
    echo " ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE \"srun -N 1 -t 90 -n 1\" " >> "$LOG_FILE"
    ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE 'srun -N 1 -t 90 -n 1' #| tee -a "$LOG_FILE"
elif [ "${MACHINE,,}" = "lassen" ]; then
    echo " ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE \"lalloc 1 -qpdebug\" " >> "$LOG_FILE"
    ./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR $MACHINE $COMPILER $BUILD_TYPE 'lalloc 1 -qpdebug' #| tee -a "$LOG_FILE"  
else    
    echo "MACHINE: ${MACHINE,,} is currently not supported. "
fi

# wait
# echo "Complete" | tee -a "$LOG_FILE"
echo " ${MACHINE,,}-${BUILD_TYPE,,}"