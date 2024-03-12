# Defining the building toolchain that are common to both GEOSX and its TPLs.
# The docker base image could be any version of ubuntu/debian (as long as package names are unchanged).
ARG DOCKER_ROOT_IMAGE

FROM ${DOCKER_ROOT_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain

# All the environment variables defined in this Dockerfile
# (GEOSX_TPL_DIR but also compiler information like CC, CXX...)
# are part of the image contract (otherwise ARG is used).
# GEOSX use them so consider modifying their names with care.
#
# The installation directory is provided as a docker build argument.
# We forward it using an environment variable.
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

# Temporary local variables dedicated to the TPL build
ENV TMP_DIR=/tmp
ENV TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ENV TPL_BUILD_DIR=${TMP_DIR}/build

# The same distribution and Dockerfile can be used for the 8, 9 and 10 version of the GNU compilers.
# The CLANG_MAJOR_VERSION argument is here to parametrise (--build-arg) the build from the `docker build` command line.
ARG CLANG_MAJOR_VERSION

# Do not apt-get upgrade (ask the maintainer if you really think something should be upgraded)
RUN apt-get update

# tzdata blocks the installation by interactively asking for the time zone.
# DEBIAN_FRONTEND and TZ variables fix this.
RUN DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
    clang-${CLANG_MAJOR_VERSION} \
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
    python3

ENV CC=/usr/bin/clang-${CLANG_MAJOR_VERSION} \
    CXX=/usr/bin/clang++-${CLANG_MAJOR_VERSION} \
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

ARG GCC_MAJOR_VERSION

ENV FC=/usr/bin/gfortran-${GCC_MAJOR_VERSION} \
    MPIFC=/usr/bin/mpifort
# Again, troublesome multi-line definition.
ENV OMPI_FC=$FC

RUN apt-get install -y --no-install-recommends \
    gfortran-${GCC_MAJOR_VERSION} \
    libtbb-dev \
    make \
    bc \
    file \
    bison \
    flex \
    ca-certificates \
    curl \
    patch

# Get host config file from docker build arguments
ARG HOST_CONFIG

# This COPY statement is a hack to use the clone that Travis-CI
# already did at the beginning of the build.
# It replaces another git clone (including the lfs) and
# prevents us from installing git, git-lfs and ca-certificates.
COPY . ${TPL_SRC_DIR}

RUN ${TPL_SRC_DIR}/docker/install_cmake.sh

# We now configure the build...
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh
# ... before we compile the TPLs!
WORKDIR ${TPL_BUILD_DIR}
RUN make

# Last step is setting everything for a complete slave that will build GEOSX.
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

# I extract the deployed TPLs from the TPL building stqge.
COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}
COPY . ${TPL_SRC_DIR}

# Any tool specific to building GEOSX shall be installed in this stage.
RUN apt-get install -y --no-install-recommends \
    openssh-client \
# `ca-certificates` is needed by `sccache` to download the cached compilations.
    ca-certificates \
    texlive \
    texlive-latex-extra \
    graphviz \
    libxml2-utils \
    git \
    ghostscript \
    ninja-build

RUN ${TPL_SRC_DIR}/docker/install_sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
