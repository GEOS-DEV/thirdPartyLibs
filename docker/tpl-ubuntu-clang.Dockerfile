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
    ca-certificates \
    curl \
    libtbb2 \
    libblas-dev \
    liblapack-dev \
    zlib1g-dev \
    openmpi-bin \
    libopenmpi-dev \
    python3

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install_cmake.sh

ENV CC=/usr/bin/clang-$CLANG_MAJOR_VERSION \
    CXX=/usr/bin/clang++-$CLANG_MAJOR_VERSION \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIEXEC=/usr/bin/mpirun
ENV OMPI_CC=$CC \
    OMPI_CXX=$CXX

# Installing TPLs
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

ARG GCC_MAJOR_VERSION

ENV FC=/usr/bin/gfortran-$GCC_MAJOR_VERSION \
    MPIFC=/usr/bin/mpifort
ENV OMPI_FC=$FC

RUN apt-get install -y --no-install-recommends \
    gfortran-$GCC_MAJOR_VERSION \
    libtbb-dev \
    make \
    bc \
    file \
    bison \
    flex \
    patch

ARG HOST_CONFIG

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/configure_tpl_build.sh
WORKDIR $BLD_DIR
RUN --mount=src=.,dst=$SRC_DIR make

# Extract only TPLs from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

RUN apt-get install -y --no-install-recommends \
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
    ninja-build

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install_sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
