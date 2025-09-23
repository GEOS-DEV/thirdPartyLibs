#!/bin/bash

## Builds the TPLs on all LC systems. Must be run from the top level TPL directory.
## Usage ./setupLC-TPL-uberenv.bash pathToInstallDirectory
INSTALL_DIR=$1

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

if [[ ! -e "scripts/uberenv/uberenv.py" ]]; then
  echo "uberenv.py script not found. Please initialize uberenv submodule first."
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

echo "Building all LC TPLs from $GEOS_BRANCH to be installed at $INSTALL_DIR..."

./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR dane gcc-12      "%gcc@12.1.1 +docs"   "salloc -N 1 -n 112 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR dane gcc-12noAVX "%gcc@12noAVX +docs"  "salloc -N 1 -n 112 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR dane gcc-13      "%gcc@13.3.1 +docs"   "salloc -N 1 -n 112 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR dane clang-14    "%clang@14.0.6 +docs" "salloc -N 1 -n 112 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR dane clang-19    "%clang@19.1.3 +docs" "salloc -N 1 -n 112 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR matrix gcc-12-cuda-12.6   "%gcc@12.1.1+cuda~uncrustify   cuda_arch=90 ^cuda@12.6.0+allow-unsupported-compilers" "salloc -N 1 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR matrix gcc-13-cuda-12.9   "%gcc@13.3.1+cuda~uncrustify   cuda_arch=90 ^cuda@12.9.1+allow-unsupported-compilers" "salloc -N 1 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR matrix clang-14-cuda-12.6 "%clang@14.0.6+cuda~uncrustify cuda_arch=90 ^cuda@12.6.0+allow-unsupported-compilers" "salloc -N 1 --exclusive -t 120 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR matrix clang-19-cuda-12.9 "%clang@19.1.3+cuda~uncrustify cuda_arch=90 ^cuda@12.9.1+allow-unsupported-compilers" "salloc -N 1 --exclusive -t 120 -A vortex" $@ &

# Note: Estimated completion time is ~90 minutes.
# Check log files for unreported completion of jobs.
wait

chmod -R g+rx $INSTALL_DIR
chgrp -R GEOS $INSTALL_DIR

echo "Complete"

