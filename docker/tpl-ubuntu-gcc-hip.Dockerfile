# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# Base image is set by workflow via DOCKER_ROOT_IMAGE
ARG DOCKER_ROOT_IMAGE=rocm/dev-ubuntu-24.04:6.4.3

FROM ${DOCKER_ROOT_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Parameters
ARG GCC_MAJOR_VERSION=13
ARG AMDGPU_TARGET=gfx942
ARG ROCM_VERSION=6.4.3

# Allow changing the number of cores used for building code via spack
ARG SPACK_BUILD_JOBS=4
ENV SPACK_BUILD_JOBS=${SPACK_BUILD_JOBS}

RUN ln -fs /usr/share/zoneinfo/America/Los_Angeles /etc/localtime && \
    apt-get update

# Install system packages
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wget \
        gnupg \
        ca-certificates \
        libtbb12 \
        libtbbmalloc2 \
        libblas-dev \
        liblapack-dev \
        libz3-dev \
        zlib1g-dev \
        libmpich-dev \
        mpich \
        python3 \
        python3-dev \
        python3-pip \
        python3-sphinx \
        doxygen \
        pkg-config \
        xz-utils \
        gettext \
        bison \
        flex \
        bzip2 \
        help2man \
        libtool \
        libgmp-dev \
        unzip \
        libmpfr-dev \
        lbzip2 \
        bzip2 \
        gnupg \
        virtualenv \
        libpugixml-dev \
        roctracer-dev \
        rocsparse-dev \
        rocsolver-dev \
        rocblas-dev \
        rocprim-dev \
        rocrand-dev \
        rocthrust-dev \
        git && \
    rm -rf /var/lib/apt/lists/*

# Install clingo for Spack (use pip without upgrading pip to avoid Debian conflict)
RUN python3 -m pip install clingo --break-system-packages

# Install CMake
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

# Hack for spack to see Ubuntu's mpich in a standard prefix layout
RUN mkdir -p /opt/mpich-system/bin /opt/mpich-system/include /opt/mpich-system/lib && \
    ln -s /usr/bin/mpicc   /opt/mpich-system/bin/mpicc && \
    ln -s /usr/bin/mpicxx  /opt/mpich-system/bin/mpicxx && \
    ln -s /usr/bin/mpif90  /opt/mpich-system/bin/mpif90 && \
    ln -s /usr/bin/mpifort /opt/mpich-system/bin/mpifort && \
    ln -s /usr/bin/mpirun  /opt/mpich-system/bin/mpirun && \
    ln -s /usr/lib/x86_64-linux-gnu/mpich/include/* /opt/mpich-system/include/ && \
    ln -s /usr/lib/x86_64-linux-gnu/mpich/lib/*     /opt/mpich-system/lib/

# Installing TPLs
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libtbb-dev \
      make \
      ninja-build \
      bc \
      file \
      patch \
      ca-certificates \
      git && \
    rm -rf /var/lib/apt/lists/*

# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
# --spack-debug to debug build
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOSX_TPL_DIR} && \
     ./scripts/uberenv/uberenv.py \
       --spec "+rocm~uncrustify~openmp~pygeosx~trilinos~petsc amdgpu_target=${AMDGPU_TARGET} generator==ninja %amdclang-18 ^caliper~papi~gotcha~sampler~libunwind~libdw" \
       --spack-env-file=${SRC_DIR}/docker/spack.yaml \
       --project-json=.uberenv_config.json \
       --prefix ${GEOSX_TPL_DIR} \
       -k && \
# Remove host-config generated for LvArray
     rm lvarray* && \
# Rename and copy spack-generated host-config to root directory
     cp *.cmake /spack-generated.cmake && \
# Remove extraneous spack files
     cd ${GEOSX_TPL_DIR} && \
     rm -rf bin/ build_stage/ misc_cache/ spack/ spack_env/ .spack-db/

# Extract only TPLs from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Extract the generated host-config
COPY --from=tpl_toolchain /spack-generated.cmake /

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends \
    openssh-client \
    ca-certificates \
    curl \
    python3 \
    texlive \
    texlive-latex-extra \
    graphviz \
    libxml2-utils \
    git \
    ghostscript \
    ninja-build \
    python3-dev \
    python3-sphinx \
    python3-mpi4py \
    python3-scipy \
    python3-virtualenv \
    python3-matplotlib \
    python3-venv \
    python3-pytest && \
    rm -rf /var/lib/apt/lists/*

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache

# Helpful environment defaults for HIP
ENV ROCM_PATH=/opt/rocm-${ROCM_VERSION}
ENV HIP_PATH=${ROCM_PATH}/hip
ENV PATH=${ROCM_PATH}/bin:${ROCM_PATH}/llvm/bin:${PATH}
ENV LD_LIBRARY_PATH=${ROCM_PATH}/lib:${ROCM_PATH}/lib64:${ROCM_PATH}/llvm/lib
ENV CMAKE_HIP_ARCHITECTURES=${AMDGPU_TARGET}