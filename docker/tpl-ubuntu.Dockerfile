# TPL build Dockerfile for Ubuntu-based images.
#
# This Dockerfile expects DOCKER_BASE_IMAGE to point at one of the geosx/ubuntu:*
# images produced by https://github.com/GEOS-DEV/docker_base_images. Those images
# already provide:
#   * the toolchain (gcc or clang) under /opt/compiler/bin/, with CC/CXX/FC set
#   * cmake (under /usr/local)
#   * the upstream NVIDIA CUDA toolkit when DOCKER_BASE_IMAGE is a CUDA variant
#
# This file is intentionally agnostic of compiler vendor and CUDA-or-not: those
# choices are baked into DOCKER_BASE_IMAGE. The matrix in
# .github/workflows/docker_build_tpls.yml selects the right base image for each
# build.

# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# Portable builds default to Open MPI. HBv4 builds select one of the two
# provider-specific manifests below; all values are validated in the image.
ARG MPI_PROVIDER=openmpi
ARG MPI_PREFIX=/opt/openmpi/5.0.10
ARG MPIEXEC_PATH=/opt/openmpi/5.0.10/bin/mpirun
ARG SPACK_ENV_FILE=docker/ubuntu-spack.yaml
ARG HBV4_BUILD=0
ARG SOURCE_SHA
ARG FINAL_IMAGE_VARIANT=portable

ARG DOCKER_BASE_IMAGE=ubuntu:24.04
FROM ${DOCKER_BASE_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR
ARG CLANG_VERSION
ARG DOCKER_BASE_IMAGE
ARG MPI_PROVIDER
ARG MPI_PREFIX
ARG MPIEXEC_PATH
ARG SPACK_ENV_FILE
ARG HBV4_BUILD
ARG SOURCE_SHA
ARG FINAL_IMAGE_VARIANT

# Install directory provided as a docker build argument; forwarded via ENV
# (GEOSX_TPL_DIR is part of the image contract consumed by GEOS).
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Fail before downloading or compiling anything if an unrecognized provider,
# manifest, or HBv4 metadata tuple was supplied. This also prevents build-arg
# paths from escaping the checked-in manifest allowlist.
RUN case "${MPI_PROVIDER}:${MPI_PREFIX}:${MPIEXEC_PATH}:${SPACK_ENV_FILE}:${HBV4_BUILD}:${FINAL_IMAGE_VARIANT}" in \
        openmpi:/opt/openmpi/5.0.10:/opt/openmpi/5.0.10/bin/mpirun:docker/ubuntu-spack.yaml:0:portable|\
        openmpi:/opt/openmpi/5.0.10:/opt/openmpi/5.0.10/bin/mpirun:docker/ubuntu-hbv4-openmpi-spack.yaml:1:hbv4|\
        mpich:/opt/mpich/5.0.1:/opt/mpich/5.0.1/bin/mpiexec:docker/ubuntu-hbv4-mpich-spack.yaml:1:hbv4) ;; \
        *) echo "ERROR: invalid MPI_PROVIDER/SPACK_ENV_FILE/HBV4_BUILD selection" >&2; exit 1 ;; \
    esac && \
    if [ "${HBV4_BUILD}" = 1 ]; then \
        printf '%s\n' "${SOURCE_SHA}" | grep -Eq '^[0-9a-f]{40}$' || \
            { echo "ERROR: SOURCE_SHA must be a 40-digit lowercase hexadecimal commit for HBv4 builds" >&2; exit 1; } && \
        printf '%s\n' "${DOCKER_BASE_IMAGE}" | grep -Eq '^.+@sha256:[0-9a-f]{64}$' || \
            { echo "ERROR: HBv4 DOCKER_BASE_IMAGE must be pinned by sha256 digest" >&2; exit 1; } ; \
    fi

# Packages needed both for the TPL build and for the downstream GEOS build.
# We avoid reinstalling anything already present in the base image (compiler,
# cmake, doxygen, blas/lapack-dev when included by base PACKAGES, etc.).
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
        bzip2 \
        ca-certificates \
        curl \
        libtbb12 \
        libgfortran5 \
        zlib1g-dev \
        python3-pip \
        python3-sphinx \
        python3-dev \
        python3-venv \
        python3-virtualenv \
        pkg-config \
        xz-utils \
        unzip \
        libmpfr-dev \
        lbzip2 \
        gnupg && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install clingo for Spack. Do not upgrade Ubuntu's Debian-managed pip in
# place; Ubuntu 24.04's pip package cannot be uninstalled by pip.
RUN python3 -m pip install --break-system-packages clingo

# For clang-based base images:
#   install a matching OpenMP runtime (libomp). MPI itself is compiled with
#   the CC/CXX/FC contract supplied by the pinned base image.
RUN if echo "${CC}" | grep -q "clang"; then \
        CLANG_MAJOR="${CLANG_VERSION:-}" ; \
        if [ -z "${CLANG_MAJOR}" ]; then \
            CLANG_MAJOR="$(echo "${CC:-}" | sed -nE 's|.*clang-([0-9]+).*|\\1|p')" ; \
        fi ; \
        if [ -z "${CLANG_MAJOR}" ] && command -v clang >/dev/null 2>&1; then \
            CLANG_MAJOR="$(clang --version | sed -nE '1s/.*version ([0-9]+).*/\\1/p')" ; \
        fi ; \
        apt-get update ; \
        if [ -n "${CLANG_MAJOR}" ]; then \
            DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
            apt-get install -y --no-install-recommends "libomp-${CLANG_MAJOR}-dev" || \
            (apt-get update && DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
             apt-get install -y --no-install-recommends libomp-dev) ; \
        else \
            DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
            apt-get install -y --no-install-recommends libomp-dev ; \
        fi ; \
        apt-get clean && rm -rf /var/lib/apt/lists/* ; \
    fi

# Install exactly one source-built MPI provider, then expose it through a
# stable path shared by the rest of this Dockerfile and downstream GEOS jobs.
RUN --mount=src=.,dst=$SRC_DIR,ro \
    if [ "${HBV4_BUILD}" = 1 ]; then \
        export HBV4_COMPILER_FLAGS='-march=native -mtune=native' \
               CFLAGS='-march=native -mtune=native' \
               CXXFLAGS='-march=native -mtune=native' \
               FCFLAGS='-march=native -mtune=native' \
               FFLAGS='-march=native -mtune=native' ; \
    fi && \
    if [ "${MPI_PROVIDER}" = openmpi ]; then \
        bash "${SRC_DIR}/docker/install-openmpi.sh" && \
        ln -s /opt/openmpi/5.0.10 /opt/mpi ; \
    else \
        bash "${SRC_DIR}/docker/install-mpich.sh" && \
        ln -s /opt/mpich/5.0.1 /opt/mpi ; \
    fi

# Common one-provider runtime contract. CUDA base images' existing library
# search path is retained when present.
ARG LD_LIBRARY_PATH
ENV MPI_PROVIDER=${MPI_PROVIDER} \
    MPI_HOME=${MPI_PREFIX} \
    MPICC=${MPI_PREFIX}/bin/mpicc \
    MPICXX=${MPI_PREFIX}/bin/mpicxx \
    MPIFC=${MPI_PREFIX}/bin/mpifort \
    MPIEXEC=${MPIEXEC_PATH} \
    PATH=${MPI_PREFIX}/bin:${PATH} \
    LD_LIBRARY_PATH=${MPI_PREFIX}/lib:${MPI_PREFIX}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}

# Build mpi4py from its verified source archive against the selected wrapper.
RUN --mount=src=.,dst=$SRC_DIR,ro \
    if [ "${HBV4_BUILD}" = 1 ]; then \
        export CFLAGS='-march=native -mtune=native' \
               CXXFLAGS='-march=native -mtune=native' \
               FCFLAGS='-march=native -mtune=native' \
               FFLAGS='-march=native -mtune=native' ; \
    fi && \
    bash "${SRC_DIR}/docker/install-mpi4py.sh"

# ----- TPL build stage -----
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR
ARG SPEC
ARG DOCKER_BASE_IMAGE
ARG MPI_PROVIDER
ARG MPI_PREFIX
ARG MPIEXEC_PATH
ARG SPACK_ENV_FILE
ARG HBV4_BUILD
ARG SOURCE_SHA

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
        libtbb-dev \
        bc \
        file \
        patch \
        git \
        autoconf \
        automake \
        libtool \
        libtool-bin \
        m4 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Run uberenv. The SPEC is supplied by the matrix because the spack toolchain
# tag depends on the compiler+version baked into the base image.
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
    mkdir -p ${GEOSX_TPL_DIR} && \
    GEOSX_SPEC="${SPEC}" && \
    if [ -z "${GEOSX_SPEC}" ] || [ "${GEOSX_SPEC}" = "undefined" ]; then \
        echo "ERROR: SPEC build-arg must be supplied" >&2 ; \
        exit 1 ; \
    fi && \
    case "${SPACK_ENV_FILE}" in \
        docker/ubuntu-spack.yaml|\
        docker/ubuntu-hbv4-openmpi-spack.yaml|\
        docker/ubuntu-hbv4-mpich-spack.yaml) ;; \
        *) echo "ERROR: unrecognized SPACK_ENV_FILE" >&2; exit 1 ;; \
    esac && \
    GEOSX_SPACK_ENV_FILE=${SRC_DIR}/${SPACK_ENV_FILE} && \
    if [ "${HBV4_BUILD}" = 1 ]; then \
        export SPACK_DISABLE_LOCAL_CONFIG=true && \
        unset SCCACHE SCCACHE_DIR RUSTC_WRAPPER ; \
    fi && \
    if echo "${CC:-}" | grep -q "clang"; then \
        GEOSX_SPACK_ENV_FILE=/tmp/geosx-spack.yaml && \
        cp ${SRC_DIR}/${SPACK_ENV_FILE} ${GEOSX_SPACK_ENV_FILE} && \
        sed -i -E "s/gcc@([0-9]+) languages:='c,c\\+\\+,fortran'/gcc@\\1 languages:='fortran'/g" ${GEOSX_SPACK_ENV_FILE} && \
        sed -i -E '/c: \/usr\/bin\/gcc-[0-9]+/d; /cxx: \/usr\/bin\/g\+\+-[0-9]+/d' ${GEOSX_SPACK_ENV_FILE} ; \
    fi && \
    if [ "${HBV4_BUILD}" = 1 ]; then \
        ./scripts/uberenv/uberenv.py \
            --spec "${GEOSX_SPEC}" \
            --spack-env-file=${GEOSX_SPACK_ENV_FILE} \
            --project-json=${SRC_DIR}/.uberenv_config.json \
            --prefix ${GEOSX_TPL_DIR} \
            --setup-and-env-only \
            -k && \
        bash "${SRC_DIR}/scripts/hbv4/install-spack-from-source.sh" \
            "${GEOSX_TPL_DIR}/spack/bin/spack" \
            "${GEOSX_TPL_DIR}/spack_env" \
            lvarray_hostconfig ; \
    else \
        ./scripts/uberenv/uberenv.py \
            --spec "${GEOSX_SPEC}" \
            --spack-env-file=${GEOSX_SPACK_ENV_FILE} \
            --project-json=${SRC_DIR}/.uberenv_config.json \
            --prefix ${GEOSX_TPL_DIR} \
            -k ; \
    fi && \
    rm -f lvarray* && \
    cp *.cmake /spack-generated.cmake && \
    cd ${GEOSX_TPL_DIR} && \
    mkdir -p /opt/GEOS/hbv4-build-evidence && \
    if [ "${HBV4_BUILD}" = 1 ]; then \
        if [ "${MPI_PROVIDER}" = openmpi ]; then MPI_VERSION=5.0.10; else MPI_VERSION=5.0.1; fi && \
        H5PCC_LIST="$(find "${GEOSX_TPL_DIR}" -path '*/bin/h5pcc' -executable -print)" && \
        [ "$(printf '%s\n' "${H5PCC_LIST}" | sed '/^$/d' | wc -l | tr -d ' ')" = 1 ] || \
            { echo "ERROR: expected exactly one executable h5pcc in the TPL install" >&2; exit 1; } && \
        SPACK_LOCK=${GEOSX_TPL_DIR}/spack_env/spack.lock && \
        [ -r "${SPACK_LOCK}" ] || \
            { echo "ERROR: generated Spack lockfile is missing" >&2; exit 1; } && \
        { find "${GEOSX_TPL_DIR}" -type f \
              \( -name spack-build-env.txt -o -name spack-build-out.txt \) \
              -exec grep -H -E -- '(-march=native|-mtune=native|CFLAGS|CXXFLAGS|FCFLAGS|FFLAGS)' {} + \
              > /tmp/hbv4-spack-build.log || true; } && \
        grep -q -- '-march=native' /tmp/hbv4-spack-build.log || \
            { echo "ERROR: native compiler flags are absent from Spack build evidence" >&2; exit 1; } && \
        HBV4_TPL_SHA="${SOURCE_SHA}" \
        HBV4_COMPILER_FLAGS='target=zen4 -march=native -mtune=native' \
        HBV4_MPI_WRAPPER="${MPI_PREFIX}/bin/mpicc" \
        HBV4_MPI_PREFIX="${MPI_PREFIX}" \
        HBV4_MPI_VERSION="${MPI_VERSION}" \
        HBV4_MPIEXEC="${MPIEXEC_PATH}" \
        HBV4_H5PCC="${H5PCC_LIST}" \
        HBV4_SPACK_BUILD_LOG=/tmp/hbv4-spack-build.log \
        bash "${SRC_DIR}/scripts/hbv4/collect-build-evidence.sh" \
            /opt/GEOS/hbv4-build-evidence \
            "${MPI_PROVIDER}" \
            "${SOURCE_SHA}" \
            "${DOCKER_BASE_IMAGE}" \
            /opt/mpi-configure-args.txt \
            "${SPACK_LOCK}" ; \
    fi && \
    rm -rf bin/ build_stage/ builtin_spack_packages_repo/ misc_cache/ spack/ spack_env/ .spack-db/

# ----- Common final GEOS-build image -----
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain_common
ARG SRC_DIR
COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR
COPY --from=tpl_toolchain /spack-generated.cmake /
COPY --from=tpl_toolchain /opt/GEOS/hbv4-build-evidence /opt/GEOS/hbv4-build-evidence

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
        openssh-client \
        git \
        graphviz \
        libxml2-utils \
        ninja-build \
        python3-scipy \
        python3-matplotlib \
        python3-pytest && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Portable images retain the existing downstream compilation cache contract.
FROM geosx_toolchain_common AS geosx_toolchain_portable
ARG SRC_DIR
RUN --mount=src=.,dst=$SRC_DIR,ro $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache

# Native HBv4 images deliberately carry neither sccache nor SCCACHE so the
# generated-code evidence always reflects a fresh native compilation.
FROM geosx_toolchain_common AS geosx_toolchain_hbv4
COPY --from=tpl_toolchain /opt/GEOS/hbv4-build-evidence/mpi-provider.json /opt/GEOS/mpi-provider.json
COPY --chmod=0755 scripts/hbv4/validate-hbv4-tpls /opt/GEOS/bin/validate-hbv4-tpls
COPY --chmod=0644 scripts/hbv4/parallel_hdf5_shared.c /opt/GEOS/bin/parallel_hdf5_shared.c

# Keep the historical final-stage name while selecting a closed variant in the
# validated build tuple above.
FROM geosx_toolchain_${FINAL_IMAGE_VARIANT} AS geosx_toolchain
