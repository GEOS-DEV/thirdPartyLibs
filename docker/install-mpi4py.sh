#!/bin/bash
set -euo pipefail

readonly MPI4PY_VERSION=4.1.2
readonly MPI4PY_SHA256=56860286dc45f20e8821e93cb06669e30462348bf866f685553fa4b712d58d02
readonly MPI4PY_ARCHIVE=mpi4py-${MPI4PY_VERSION}.tar.gz
readonly MPI4PY_URL=https://files.pythonhosted.org/packages/source/m/mpi4py/${MPI4PY_ARCHIVE}

: "${MPICC:?MPICC must name the selected MPI C compiler wrapper}"
: "${MPI_HOME:?MPI_HOME must name the selected MPI prefix}"

build_dir=$(mktemp -d /tmp/mpi4py-build.XXXXXX)
trap 'rm -rf "${build_dir}"' EXIT

curl --fail --location --silent --show-error \
    --output "${build_dir}/${MPI4PY_ARCHIVE}" \
    "${MPI4PY_URL}"
echo "${MPI4PY_SHA256}  ${build_dir}/${MPI4PY_ARCHIVE}" | sha256sum --check --strict

MPICC="${MPICC}" python3 -m pip install \
    --break-system-packages \
    --no-cache-dir \
    --no-binary=mpi4py \
    "${build_dir}/${MPI4PY_ARCHIVE}"

mpi4py_extension=$(python3 - <<'PY'
import mpi4py
from mpi4py import MPI

assert mpi4py.__version__ == "4.1.2"
print(MPI.__file__)
print(MPI.Get_library_version().replace("\n", " "))
PY
)
extension_path=${mpi4py_extension%%$'\n'*}
[[ -f "${extension_path}" ]] || {
    echo "mpi4py extension is missing: ${extension_path}" >&2
    exit 1
}
mapfile -t linked_mpi < <(
    ldd "${extension_path}" | awk '
      /(^|[[:space:]])libmpi[^[:space:]]*/ {
        for (i = 1; i <= NF; ++i) if ($i == "=>") print $(i + 1)
      }'
)
(( ${#linked_mpi[@]} > 0 )) || {
    echo 'mpi4py has no dynamic libmpi dependency' >&2
    exit 1
}
for library in "${linked_mpi[@]}"; do
    library=$(readlink -f "${library}")
    [[ "${library}" == "${MPI_HOME}"/* ]] || {
        echo "mpi4py resolves libmpi outside ${MPI_HOME}: ${library}" >&2
        exit 1
    }
done
printf '%s\n' "${mpi4py_extension#*$'\n'}"
