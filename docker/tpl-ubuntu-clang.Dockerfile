# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

ARG DOCKER_ROOT_IMAGE

FROM $DOCKER_ROOT_IMAGE AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

ARG CLANG_MAJOR_VERSION

RUN apt-get update

# Installing dependencies
RUN DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
    clang-$CLANG_MAJOR_VERSION \
    libomp-$CLANG_MAJOR_VERSION-dev \
    ca-certificates \
    curl \
    libtbb2 \
    libblas-dev \
    liblapack-dev \
    zlib1g-dev \
    openmpi-bin \
    libopenmpi-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-sphinx \
    doxygen \
    pkg-config \
    xz-utils \
    unzip \
    libmpfr-dev \
    lbzip2 \
    bzip2 \
    gnupg \
    virtualenv

# Install clingo for Spack
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install clingo

# Install CMake
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

# Installing TPLs
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

ARG GCC_MAJOR_VERSION

RUN apt-get install -y --no-install-recommends \
    gfortran-$GCC_MAJOR_VERSION \
    libtbb-dev \
    make \
    bc \
    file \
    bison \
    flex \
# GEOS patches some tpl. Remove when it's not the case anymore.
    patch \
# `ca-certificates`  needed by `git` to download spack repo.
    ca-certificates \
    git

# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOSX_TPL_DIR} && \
     ./scripts/uberenv/uberenv.py \
       --spec "%clang@${CLANG_MAJOR_VERSION} ~shared~openmp+docs ^caliper~gotcha~sampler~libunwind~libdw~papi" \
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

RUN DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
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
## Necessary dependencies for pygeosx unit tests
    python3-dev \
    python3-sphinx \
    python3-mpi4py \
    python3-scipy \
    python3-virtualenv \
    python3-matplotlib \
    python3-venv \
    python3-pytest

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
