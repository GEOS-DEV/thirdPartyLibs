#!/bin/bash
set -euo pipefail

readonly MPICH_VERSION=5.0.1
readonly MPICH_SHA256=8c1832a13ddacf071685069f5fadfd1f2877a29e1a628652892c65211b1f3327
readonly MPICH_PREFIX=/opt/mpich/${MPICH_VERSION}
readonly MPICH_ARCHIVE=mpich-${MPICH_VERSION}.tar.gz
readonly MPICH_URL=https://www.mpich.org/static/downloads/${MPICH_VERSION}/${MPICH_ARCHIVE}

configure_args=(
    "--prefix=${MPICH_PREFIX}"
    '--with-device=ch4:ofi'
    '--with-libfabric=embedded'
    '--enable-romio'
    '--with-pm=hydra'
    '--enable-shared'
    '--disable-static'
)
if [[ -n "${HBV4_COMPILER_FLAGS:-}" ]]; then
    export MPICH_MPICC_CFLAGS="${HBV4_COMPILER_FLAGS}"
    export MPICH_MPICXX_CXXFLAGS="${HBV4_COMPILER_FLAGS}"
    export MPICH_MPIF77_FFLAGS="${HBV4_COMPILER_FLAGS}"
    export MPICH_MPIFORT_FCFLAGS="${HBV4_COMPILER_FLAGS}"
fi
{
    if [[ -n "${HBV4_COMPILER_FLAGS:-}" ]]; then
        printf 'CFLAGS=%s\nCXXFLAGS=%s\nFCFLAGS=%s\nFFLAGS=%s\n' \
            "${CFLAGS}" "${CXXFLAGS}" "${FCFLAGS}" "${FFLAGS}"
        printf 'MPICH_MPICC_CFLAGS=%s\nMPICH_MPICXX_CXXFLAGS=%s\nMPICH_MPIF77_FFLAGS=%s\nMPICH_MPIFORT_FCFLAGS=%s\n' \
            "${MPICH_MPICC_CFLAGS}" "${MPICH_MPICXX_CXXFLAGS}" \
            "${MPICH_MPIF77_FFLAGS}" "${MPICH_MPIFORT_FCFLAGS}"
    fi
    printf '%s\n' "${configure_args[@]}"
} > /opt/mpi-configure-args.txt

build_dir=$(mktemp -d /tmp/mpich-build.XXXXXX)
trap 'rm -rf "${build_dir}"' EXIT

curl --fail --location --silent --show-error \
    --output "${build_dir}/${MPICH_ARCHIVE}" \
    "${MPICH_URL}"
echo "${MPICH_SHA256}  ${build_dir}/${MPICH_ARCHIVE}" | sha256sum --check --strict

tar -xzf "${build_dir}/${MPICH_ARCHIVE}" -C "${build_dir}"
cd "${build_dir}/mpich-${MPICH_VERSION}"

./configure "${configure_args[@]}"
make -j"$(nproc)"
make install

"${MPICH_PREFIX}/bin/mpichversion"
"${MPICH_PREFIX}/bin/mpicc" -show
