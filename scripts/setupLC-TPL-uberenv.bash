#!/bin/bash

## Builds the TPLs on all LC systems. Must be run from the top level TPL directory.
## Usage ./setupLC-TPL.bash branchToBuild pathToInstallDirectory [extra arguments to config-build ]
GEOS_BRANCH=$1
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

# Check if branch exists
branch_exists=$(git ls-remote https://github.com/GEOS-DEV/GEOS.git $GEOS_BRANCH | wc -l)

if [[ $branch_exists != 1 ]] ; then
    echo "Branch $GEOS_BRANCH does not exist in GEOS repository"
    exit
fi

if [[ -z $INSTALL_DIR ]]; then
    echo "No installation directory path was provided"
    exit
fi

if [[ ! -d $INSTALL_DIR ]]; then
  echo "Installation directory $INSTALL_DIR does not exist. Please initialize first."
  exit
fi

if [[ ! "$INSTALL_DIR" = /* ]]; then
  echo "Installation directory $INSTALL_DIR must be an absolute path."
  exit
fi

# Clone GEOS repo to build with uberenv
echo "Cloning branch $GEOS_BRANCH in temporary GEOS repo directory tempGEOS to build TPLs with uberenv..."
rm -rf tempGEOS
git clone -b $GEOS_BRANCH https://github.com/GEOS-DEV/GEOS.git tempGEOS

cd tempGEOS
git submodule init scripts/uberenv
git submodule init src/cmake/blt
git submodule init src/coreComponents/LvArray
git submodule update
cd ..

echo "Building all LC TPLs from $GEOS_BRANCH to be installed at $INSTALL_DIR"
chmod -R g+rx $INSTALL_DIR
chgrp -R GEOS $INSTALL_DIR
# ./scripts/setupLC-TPL-helper.bash $GEOS_BRANCH $INSTALL_DIR quartz clang-14 "%clang@14.0.6 +docs" "srun -N 1 -t 150 -n 1 -A geosecp" $@ &
# ./scripts/setupLC-TPL-helper.bash $GEOS_BRANCH $INSTALL_DIR quartz gcc-12 "%gcc@12.1.1 +docs" "srun -N 1 -t 150 -n 1 -A geosecp" $@ &
# ./scripts/setupLC-TPL-helper.bash $GEOS_BRANCH $INSTALL_DIR lassen gcc-8-cuda-11 "%gcc@8.3.1+cuda~uncrustify cuda_arch=70 ^cuda@11.8.0+allow-unsupported-compilers" "lalloc 1 -W 150" $@ &
# ./scripts/setupLC-TPL-helper.bash $GEOS_BRANCH $INSTALL_DIR lassen clang-13-cuda-11 "%clang@13.0.1+cuda~uncrustify cuda_arch=70 ^cuda@11.8.0+allow-unsupported-compilers" "lalloc 1 -W 150" $@ &
# ./scripts/setupLC-TPL-helper.bash $GEOS_BRANCH $INSTALL_DIR lassen clang-10-cuda-11 "%clang@10.0.1+cuda~uncrustify cuda_arch=70" "lalloc 1 -W 150" $@ &

wait
echo "Removing temporary GEOS repo tempGEOS..."
rm -rf tempGEOS

echo "Complete"

