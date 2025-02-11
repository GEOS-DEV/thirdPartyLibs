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

./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR ruby clang-14 "%clang@14.0.6 +docs" "salloc -N 1 -n 1 -t 150 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR ruby gcc-12 "%gcc@12.1.1 +docs" "salloc -N 1 -n 1 -t 150 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR ruby gcc-12noAVX "%gcc@12noAVX +docs" "salloc -N 1 -n 1 -t 150 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR dane gcc-12 "%gcc@12.1.1 +docs" "salloc -N 1 -n 1 -t 150 -A vortex" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR lassen gcc-8-cuda-11 "%gcc@8.3.1+cuda~uncrustify cuda_arch=70 ^cuda@11.8.0+allow-unsupported-compilers" "lalloc 1 -W 150" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR lassen clang-13-cuda-11 "%clang@13.0.1+cuda~uncrustify cuda_arch=70 ^cuda@11.8.0+allow-unsupported-compilers" "lalloc 1 -W 150" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR lassen clang-10-cuda-11 "%clang@10.0.1+cuda~uncrustify cuda_arch=70 ^cuda@11.8.0+allow-unsupported-compilers" "lalloc 1 -W 150" $@ &
./scripts/setupLC-TPL-uberenv-helper.bash $INSTALL_DIR lassen clang-13-cuda-12 "%clang@13.0.1+cuda~uncrustify cuda_arch=70 ^cuda@12.0.0+allow-unsupported-compilers" "lalloc 1 -W 150" $@ &

# Note: Estimated completion time is ~90 minutes.
# Check log files for unreported completion of jobs.
wait

chmod -R g+rx $INSTALL_DIR
chgrp -R GEOS $INSTALL_DIR

echo "Complete"

