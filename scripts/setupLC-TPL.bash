#!/bin/bash

## Builds the TPLs on all LC systems. Must be run from the top level TPL directory.
## Usage ./setupLC-TPL.bash pathToGeosDirectory pathToInstallDirectory [extra arguments to config-build ]
GEOS_DIR=$1
INSTALL_DIR=$2

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

mkdir toBeDeleted
mv build-* toBeDeleted
rm -rf toBeDeleted &

echo "Building all LC TPLs from $GEOS_DIR to be installed at $INSTALL_DIR"
chmod -R g+rx $INSTALL_DIR
chgrp -R GEOS $INSTALL_DIR
./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR ruby clang-14           "3.26.3" "srun -N 1 -t 90 -n 1 -A vortex" $@ &
./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR ruby gcc-12             "3.26.3" "srun -N 1 -t 90 -n 1 -A vortex" $@ &
./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR lassen gcc-8-cuda-11    "3.26.3" "lalloc 1 -qpdebug"  $@ &
./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR lassen clang-13-cuda-11 "3.29.2" "lalloc 1 -qpdebug"  $@ &
./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR lassen clang-10-cuda-11 "3.29.2" "lalloc 1 -qpdebug"  $@ &
./scripts/setupLC-TPL-helper.bash $GEOS_DIR $INSTALL_DIR lassen clang-13-cuda-12 "3.29.2" "lalloc 1 -qpdebug"  $@ &

wait
echo "Complete"
