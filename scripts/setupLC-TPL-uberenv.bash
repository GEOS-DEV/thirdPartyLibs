#!/bin/bash

## Builds the TPLs on specified LC systems.
## Usage: ./setupLC-TPL-uberenv.bash <InstallDir> [MachineList] [ExtraArgs...]
##
##   InstallDir:  Absolute path to the installation directory.
##   MachineList: (Optional) Comma-separated list of machines to build on
##                (e.g., "dane,matrix"). Defaults to all.
##   ExtraArgs:   (Optional) Additional arguments forwarded to the helper script.
##                Use --no-permissions to skip all chmod/chgrp calls.
##                Use --clean to clean data from previous build.

# --- Configuration ---
# All known machines. Add new machine names here.
declare -a ALL_MACHINES=("dane" "matrix" "tuolumne")

# --- Argument Parsing ---
INSTALL_DIR=$1
MACHINE_LIST_STR=${2:-"all"} # Default to "all" if the second argument is not provided

# Validate INSTALL_DIR before proceeding
if [[ -z "$INSTALL_DIR" ]]; then
  echo "ERROR: No installation directory path was provided." >&2
  exit 1
fi
if [[ ! -d "$INSTALL_DIR" ]]; then
  echo "ERROR: Installation directory '$INSTALL_DIR' does not exist." >&2
  exit 1
fi
if [[ ! "$INSTALL_DIR" = /* ]]; then
  echo "ERROR: Installation directory must be an absolute path." >&2
  exit 1
fi

# Eat up the first two arguments so the rest can be forwarded.
shift 2 2>/dev/null

# --- Initialize Control Variable and Parse Extra Arguments ---
SET_PERMISSIONS=true
declare -a FORWARDED_ARGS=()

# Loop through remaining args, filter out our flag, and collect the rest.
for arg in "$@"; do
  if [[ "$arg" == "--no-permissions" ]]; then
    SET_PERMISSIONS=false
  fi
  FORWARDED_ARGS+=("$arg")
done

# --- Setup ---
# Check for uberenv script
if [[ ! -e "scripts/uberenv/uberenv.py" ]]; then
  echo "ERROR: uberenv.py script not found. Please initialize uberenv submodule first." >&2
  exit 1
fi

# Determine which machines to run on
declare -a MACHINES_TO_RUN
if [[ "$MACHINE_LIST_STR" == "all" ]]; then
  MACHINES_TO_RUN=("${ALL_MACHINES[@]}")
else
  # Convert comma-separated string to array
  IFS=',' read -r -a MACHINES_TO_RUN <<< "$MACHINE_LIST_STR"
fi

# --- Functions ---
# Trap the interrupt signal and kill all children.
trap 'kill_children' INT

function kill_children() {
  trap '' INT TERM # Ignore signals while shutting down
  echo -e "\n**** Shutting down. Sending TERM signal to child processes ****"
  # Kill the entire process group, which includes all background jobs
  kill -TERM 0
  wait
  echo "DONE"
}

# Function to launch jobs for a specific machine
function launch_jobs() {
  local machine=$1
  shift # The rest of $@ are the forwarded arguments
  local UBERENV_HELPER="./scripts/setupLC-TPL-uberenv-helper.bash"
  local COMMON="^vtk generator=ninja"

  echo "-----> Launching jobs for [${machine}]..."

  # Note: The max. time allowed on the debug queue is 1h. If we need more, switch to pbatch
  case "$machine" in
    dane)
      ALLOC_CMD="salloc -N 1 --exclusive -t 60 -A vortex -ppdebug"
      "${UBERENV_HELPER}" "$INSTALL_DIR" dane gcc-12                "+docs %gcc-12 ${COMMON}"        "${ALLOC_CMD}" "$@" &
      "${UBERENV_HELPER}" "$INSTALL_DIR" dane gcc-13                "+docs %gcc-13 ${COMMON}"        "${ALLOC_CMD}" "$@" &
      "${UBERENV_HELPER}" "$INSTALL_DIR" dane llvm-14               "+docs %clang-14 ${COMMON}"      "${ALLOC_CMD}" "$@" &
      "${UBERENV_HELPER}" "$INSTALL_DIR" dane llvm-19               "+docs %clang-19 ${COMMON}"      "${ALLOC_CMD}" "$@" &
      ;;

    matrix)
      ALLOC_CMD="salloc -N 1 --exclusive -t 60 -A vortex -ppdebug"
      "${UBERENV_HELPER}" "$INSTALL_DIR" matrix gcc-12-cuda-12.6    "+cuda~uncrustify cuda_arch=90 %gcc-12 ^cuda@12.6.0+allow-unsupported-compilers ${COMMON}"   "${ALLOC_CMD}" "$@" &
      "${UBERENV_HELPER}" "$INSTALL_DIR" matrix gcc-13-cuda-12.9    "+cuda~uncrustify cuda_arch=90 %gcc-13 ^cuda@12.9.1+allow-unsupported-compilers ${COMMON}"   "${ALLOC_CMD}" "$@" &
      "${UBERENV_HELPER}" "$INSTALL_DIR" matrix llvm-14-cuda-12.6   "+cuda~uncrustify cuda_arch=90 %clang-14 ^cuda@12.6.0+allow-unsupported-compilers ${COMMON}" "${ALLOC_CMD}" "$@" &
      "${UBERENV_HELPER}" "$INSTALL_DIR" matrix llvm-19-cuda-12.9   "+cuda~uncrustify cuda_arch=90 %clang-19 ^cuda@12.9.1+allow-unsupported-compilers ${COMMON}" "${ALLOC_CMD}" "$@" &
      ;;

    tuo|tuolumne)
      ALLOC_CMD="salloc -N 1 --exclusive -t 60 -A vortex -ppdebug"
      "${UBERENV_HELPER}" "$INSTALL_DIR" tuolumne cce-20-rocm-6.4.2  "+rocm~pygeosx~trilinos~petsc~docs amdgpu_target=gfx942 %cce-20 ${COMMON}" "${ALLOC_CMD}" "$@" &
      "${UBERENV_HELPER}" "$INSTALL_DIR" tuolumne llvm-amdgpu-6.4.2-rocm-6.4.2  "+rocm~pygeosx~trilinos~petsc~docs amdgpu_target=gfx942 %llvm-amdgpu_6_4_2 ${COMMON}" "${ALLOC_CMD}" "$@" &
      ;;

    *)
      echo "WARNING: Unknown machine '$machine'. Skipping." >&2
      ;;
  esac
}

# --- Main Execution ---
echo "Building TPLs for machines: ${MACHINES_TO_RUN[*]}"
echo "Installation directory: $INSTALL_DIR"
echo "Forwarded arguments: ${FORWARDED_ARGS[*]}"
if [ "$SET_PERMISSIONS" = false ]; then
    echo "Permissions: SKIPPING all chmod/chgrp calls."
fi
echo "---"

for machine in "${MACHINES_TO_RUN[@]}"; do
  launch_jobs "$machine" "${FORWARDED_ARGS[@]}"
done

echo "All jobs launched. Waiting for completion..."
# Note: Estimated completion time is ~90 minutes.
# Check log files for unreported completion of jobs.
wait

# --- Conditionally Set Final Permissions ---
if [ "$SET_PERMISSIONS" = true ]; then
  echo "---"
  echo "Finalizing permissions..."
  chmod -R g+rx "$INSTALL_DIR"
  chgrp -R GEOS "$INSTALL_DIR"
else
    echo "---"
    echo "Skipping final permission updates as requested."
fi

echo "Complete."
