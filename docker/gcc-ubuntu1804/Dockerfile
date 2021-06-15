# Defining the building toolchain that are common to both GEOSX and its TPLs.
FROM ubuntu:18.04 AS tpl_toolchain_intersect_geosx_toolchain

# All the environment variables defined in this Dockerfile
# (GEOSX_TPL_DIR but also compiler information like CC, CXX...)
# are part of the image contract (otherwise ARG is used).
# GEOSX use them so consider modifying their names with care.
#
# The installation directory is provided as a docker build argument.
# We forward it using an environment variable.
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

# Do not apt-get upgrade (ask the maintainer if you really think something should be upgraded)
RUN apt-get update

RUN apt-get install -y --no-install-recommends \
    make \
    gcc-8 \
    g++-8 \
    libgfortran5 \
# Several scientific (or close) libraries.
# Note the difference between runtime and development packages.
    libtbb2 \
    libblas-dev \
    liblapack-dev \
    zlib1g-dev \
    openmpi-bin \
    libopenmpi-dev \
# Some of the TPL's make "extensive" use of python in their build.
# And we want to test GEOSX's python configuration script.
# Unfortunately argparse (standard library's package used by GEOSX)
# is not in the python-minimal package so we install the whole std lib.
    python

# Installing more recent cmake version (3.10.2 in ubuntu is not enough)
ARG CMAKE_VERSION=3.14.5
# We install (and uninstall) `curl` and some SSL certificates only for downloading `cmake`.
RUN apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -fsSL https://cmake.org/files/v${CMAKE_VERSION%.[0-9]*}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz | tar --directory=/usr/local --strip-components=1 -xzf - && \
    apt-get purge --auto-remove -y curl ca-certificates

ENV CC=/usr/bin/gcc-8 \
    CXX=/usr/bin/g++-8 \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIEXEC=/usr/bin/mpirun
# The multi-line definition of arguments does not seem happy
# when a variable uses the value of another variable previously defined on the same line.
ENV OMPI_CC=$CC \
    OMPI_CXX=$CXX

# This stage is dedicated to TPLs uniquely.
# A multi-stage build patern will allow to extract what we need for the GEOSX build.
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

ENV FC=/usr/bin/gfortran-8 \
    MPIFC=/usr/bin/mpifort
# Again, troublesome multi-line definition.
ENV OMPI_FC=$FC

RUN apt-get install -y --no-install-recommends \
    libtbb-dev \
    gfortran-8 \
    bc \
    file \
    bison \
    flex \
# GEOSX patches some tpl. Remove when it's not the case anymore.
    patch

# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ARG TPL_BUILD_DIR=${TMP_DIR}/build
# Get host config file from docker build arguments
ARG HOST_CONFIG

# This COPY statement is a hack to use the clone that Travis-CI
# already did at the beginning of the build.
# It replaces another git clone (including the lfs) and
# prevents us from installing git, git-lfs and ca-certificates.
COPY . ${TPL_SRC_DIR}
# We now configure the build...
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh
# ... before we compile the TPLs!
WORKDIR ${TPL_BUILD_DIR}
RUN make

# Last step is setting everything for a complete slave that will build GEOSX.
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

# I extract the deployed TPLs from the TPL building stqge.
COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

# Any tool specific to building GEOSX shall be installed in this stage.
RUN apt-get install -y --no-install-recommends \
    openssh-client \
    texlive \
    texlive-latex-extra \
    graphviz \
    libxml2-utils \
    git \
    ghostscript
