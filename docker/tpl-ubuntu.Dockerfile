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

ARG DOCKER_BASE_IMAGE=ubuntu:24.04
FROM ${DOCKER_BASE_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

# Install directory provided as a docker build argument; forwarded via ENV
# (GEOSX_TPL_DIR is part of the image contract consumed by GEOS).
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Packages needed both for the TPL build and for the downstream GEOS build.
# We avoid reinstalling anything already present in the base image (compiler,
# cmake, doxygen, blas/lapack-dev when included by base PACKAGES, etc.).
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        libtbb12 \
        libgfortran5 \
        zlib1g-dev \
        doxygen \
        openmpi-bin \
        libopenmpi-dev \
        python3 \
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
        bzip2 \
        gnupg && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install clingo for Spack. Do not upgrade Ubuntu's Debian-managed pip in
# place; Ubuntu 24.04's pip package cannot be uninstalled by pip.
RUN python3 -m pip install --break-system-packages clingo

# MPI environment. CC/CXX/FC come from the base image.
ENV MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIEXEC=/usr/bin/mpirun
ENV OMPI_CC=${CC} \
    OMPI_CXX=${CXX}

# Ubuntu OpenMPI defaults wrappers to gcc/g++. For clang-based base images we
# retarget the wrappers to clang/clang++ so mpi wrapper compilers are aligned
# with the image toolchain contract.
RUN if echo "${CC}" | grep -q "clang"; then \
        for f in /usr/share/openmpi/mpicc-wrapper-data.txt /usr/share/openmpi/mpicc.openmpi-wrapper-data.txt; do \
            if [ -f "${f}" ]; then sed -i "s|^compiler=.*$|compiler=${CC}|" "${f}" ; fi ; \
        done && \
        for f in /usr/share/openmpi/mpic++-wrapper-data.txt /usr/share/openmpi/mpic++.openmpi-wrapper-data.txt /usr/share/openmpi/mpicxx-wrapper-data.txt /usr/share/openmpi/mpicxx.openmpi-wrapper-data.txt /usr/share/openmpi/mpiCC-wrapper-data.txt /usr/share/openmpi/mpiCC.openmpi-wrapper-data.txt; do \
            if [ -f "${f}" ]; then sed -i "s|^compiler=.*$|compiler=${CXX}|" "${f}" ; fi ; \
        done && \
        mpicc --showme:command && \
        mpic++ --showme:command ; \
    fi

# ----- TPL build stage -----
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR
ARG SPEC

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
        libtbb-dev \
        make \
        bc \
        file \
        patch \
        git \
        autoconf \
        automake \
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
    GEOSX_SPACK_ENV_FILE=${SRC_DIR}/docker/ubuntu-spack.yaml && \
    if echo "${CC:-}" | grep -q "clang"; then \
        GEOSX_SPACK_ENV_FILE=/tmp/geosx-spack.yaml && \
        cp ${SRC_DIR}/docker/ubuntu-spack.yaml ${GEOSX_SPACK_ENV_FILE} && \
        sed -i -E "s/gcc@([0-9]+) languages:='c,c\\+\\+,fortran'/gcc@\\1 languages:='fortran'/g" ${GEOSX_SPACK_ENV_FILE} && \
        sed -i -E '/c: \/usr\/bin\/gcc-[0-9]+/d; /cxx: \/usr\/bin\/g\+\+-[0-9]+/d' ${GEOSX_SPACK_ENV_FILE} ; \
    fi && \
    ./scripts/uberenv/uberenv.py \
        --spec "${GEOSX_SPEC}" \
        --spack-env-file=${GEOSX_SPACK_ENV_FILE} \
        --project-json=${SRC_DIR}/.uberenv_config.json \
        --prefix ${GEOSX_TPL_DIR} \
        -k && \
    rm -f lvarray* && \
    cp *.cmake /spack-generated.cmake && \
    cd ${GEOSX_TPL_DIR} && \
    rm -rf bin/ build_stage/ builtin_spack_packages_repo/ misc_cache/ spack/ spack_env/ .spack-db/

# ----- Final GEOS-build image -----
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR
COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR
COPY --from=tpl_toolchain /spack-generated.cmake /

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
        openssh-client \
        git \
        texlive \
        texlive-latex-extra \
        graphviz \
        libxml2-utils \
        ghostscript \
        ninja-build \
        python3-mpi4py \
        python3-scipy \
        python3-matplotlib \
        python3-pytest && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install sccache to speed up downstream GEOS builds
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
