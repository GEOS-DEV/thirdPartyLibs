#!/bin/bash
set -euo pipefail

readonly OPENMPI_VERSION=5.0.10
readonly OPENMPI_SHA256=0acecc4fc218e5debdbcb8a41d182c6b0f1d29393015ed763b2a91d5d7374cc6
readonly OPENMPI_PREFIX=/opt/openmpi/${OPENMPI_VERSION}
readonly OPENMPI_ARCHIVE=openmpi-${OPENMPI_VERSION}.tar.bz2
readonly OPENMPI_URL=https://download.open-mpi.org/release/open-mpi/v5.0/${OPENMPI_ARCHIVE}

configure_args=(
    "--prefix=${OPENMPI_PREFIX}"
    '--enable-shared'
    '--disable-static'
    '--enable-mpi-fortran=all'
    '--enable-io-romio'
)
if [[ -n "${HBV4_COMPILER_FLAGS:-}" ]]; then
    configure_args+=(
        "--with-wrapper-cflags=${HBV4_COMPILER_FLAGS}"
        "--with-wrapper-cxxflags=${HBV4_COMPILER_FLAGS}"
        "--with-wrapper-fcflags=${HBV4_COMPILER_FLAGS}"
    )
fi
{
    if [[ -n "${HBV4_COMPILER_FLAGS:-}" ]]; then
        printf 'CFLAGS=%s\nCXXFLAGS=%s\nFCFLAGS=%s\nFFLAGS=%s\n' \
            "${CFLAGS}" "${CXXFLAGS}" "${FCFLAGS}" "${FFLAGS}"
    fi
    printf '%s\n' "${configure_args[@]}"
} > /opt/mpi-configure-args.txt

build_dir=$(mktemp -d /tmp/openmpi-build.XXXXXX)
trap 'rm -rf "${build_dir}"' EXIT

curl --fail --location --silent --show-error \
    --output "${build_dir}/${OPENMPI_ARCHIVE}" \
    "${OPENMPI_URL}"
echo "${OPENMPI_SHA256}  ${build_dir}/${OPENMPI_ARCHIVE}" | sha256sum --check --strict

tar -xjf "${build_dir}/${OPENMPI_ARCHIVE}" -C "${build_dir}"
cd "${build_dir}/openmpi-${OPENMPI_VERSION}"

./configure "${configure_args[@]}"
make -j"$(nproc)"
make install

# Both MPI-IO implementations are built; select OMPIO unless a caller explicitly
# overrides the MCA parameter at runtime.
printf '%s\n' 'io = ompio' >> "${OPENMPI_PREFIX}/etc/openmpi-mca-params.conf"

ompi_io_components=$("${OPENMPI_PREFIX}/bin/ompi_info" --param io all)
grep -q 'MCA io: ompio' <<<"${ompi_io_components}"
grep -q 'MCA io: romio341' <<<"${ompi_io_components}"
"${OPENMPI_PREFIX}/bin/mpicc" --showme:command
