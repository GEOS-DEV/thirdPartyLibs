#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
export LC_ALL=C

die() { printf 'capture-mpi-wrapper-show: ERROR: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 3 ]] || die 'usage: capture-mpi-wrapper-show.sh PROVIDER MPI_WRAPPER OUTPUT_FILE'

provider=$1
mpi_wrapper=$2
output_file=$3

[[ -x "$mpi_wrapper" ]] || die "MPI wrapper is not executable: $mpi_wrapper"
[[ -n "$output_file" ]] || die 'output file must not be empty'

# Open MPI's mpicc is a symlink to opal_wrapper. The generic wrapper selects
# its configuration from argv[0], so execute the reviewed mpicc path rather
# than its readlink-resolved target. MPICH uses its provider-specific -show
# interface; Open MPI documents --showme for the equivalent full command.
case "$provider" in
  openmpi)
    "$mpi_wrapper" --showme >"$output_file" 2>&1 ||
      die 'Open MPI wrapper --showme command failed'
    ;;
  mpich)
    "$mpi_wrapper" -show >"$output_file" 2>&1 ||
      die 'MPICH wrapper -show command failed'
    ;;
  *) die 'PROVIDER must be openmpi or mpich' ;;
esac

[[ -s "$output_file" ]] || die 'MPI wrapper show command produced no evidence'
