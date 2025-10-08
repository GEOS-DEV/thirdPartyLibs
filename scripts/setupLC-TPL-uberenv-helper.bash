#!/bin/bash

## Builds the TPLs for a specific system and host config.
## Usage ./setupLC-TPL-uberenv-helper.bash <InstallDir> <Machine> <Compiler> <SpackSpec> <AllocCmd> [ExtraArgs...]

# --- 1. Initialize Control Variable ---
# By default, we will set permissions.
SET_PERMISSIONS=true

# --- Argument Parsing ---
INSTALL_DIR=$1
MACHINE=$2
COMPILER=$3
SPEC=\"${4}\"
GET_A_NODE=$5

# Eat up the primary arguments; the rest in $@ are forwarded.
shift 5

# --- 2. Check for the --no-permissions Flag ---
# Loop through the forwarded arguments to find our flag.
for arg in "$@"; do
  if [[ "$arg" == "--no-permissions" ]]; then
    SET_PERMISSIONS=false
    echo "Found --no-permissions flag. Will skip permission updates."
    break
  fi
done

# --- Main Execution ---
CONFIG=$MACHINE-$COMPILER
LOG_FILE=$CONFIG.log

echo "Building the TPLs on $MACHINE for $COMPILER to be installed at $INSTALL_DIR. Progress will be written to $LOG_FILE."

# Note: The ssh command forwards the extra arguments ($@) to uberenv.py
ssh "$MACHINE" -t "
. /etc/profile &&
cd \"$PWD\" &&
$GET_A_NODE ./scripts/uberenv/uberenv.py --spec ${SPEC} --prefix \"${INSTALL_DIR}/${CONFIG}_tpls\" --spack-env-name \"${CONFIG}_env\" \"$@\" &&
exit" > "$LOG_FILE" 2>&1

## Check the last ten lines of the log file.
## A successful install should show up on one of the final lines.
tail -10 "$LOG_FILE" | grep -E "Successfully installed geos" > /dev/null
if [ $? -eq 0 ]; then
  echo "Cleanup extra build files at ${INSTALL_DIR}/${CONFIG}_tpls/."
  rm -rf "${INSTALL_DIR}/${CONFIG}_tpls/${CONFIG}_env"
  rm -rf "${INSTALL_DIR}/${CONFIG}_tpls/.spack-db"
  rm -rf "${INSTALL_DIR}/${CONFIG}_tpls/misc_cache"
  rm -rf "${INSTALL_DIR}/${CONFIG}_tpls/spack"
  rm -rf "${INSTALL_DIR}/${CONFIG}_tpls/builtin_spack_packages_repo"
  rm -rf "${INSTALL_DIR}/${CONFIG}_tpls/build_stage"

  # --- 3. Conditionally Set Permissions ---
  if [ "$SET_PERMISSIONS" = true ]; then
    echo "Updating file permissions at ${INSTALL_DIR}/${CONFIG}_tpls/."
    # Install directory root
    chmod g+rx "$INSTALL_DIR"
    chgrp GEOS "$INSTALL_DIR"

    # Update only executable and library directories to avoid NFS errors
    chmod g+rx -R "${INSTALL_DIR}/${CONFIG}_tpls/bin"
    chgrp GEOS -R "${INSTALL_DIR}/${CONFIG}_tpls/bin"
    chmod g+rx -R "${INSTALL_DIR}/${CONFIG}_tpls/${COMPILER%%-*}"*
    chgrp GEOS -R "${INSTALL_DIR}/${CONFIG}_tpls/${COMPILER%%-*}"*
  else
    echo "Skipping permission updates as requested."
  fi

  echo "Build of ${CONFIG} completed successfully."
  exit 0
else
  echo "Build of ${CONFIG} seemed to fail, check $LOG_FILE."
  exit 1
fi
