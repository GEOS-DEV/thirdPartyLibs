# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# Defining the building toolchain that are common to both GEOS and its TPLs.
# The docker base image could be any version of ubuntu/debian (as long as package names are unchanged).
ARG DOCKER_ROOT_IMAGE


FROM $DOCKER_ROOT_IMAGE AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

# All the environment variables defined in this Dockerfile
# (GEOSX_TPL_DIR but also compiler information like CC, CXX...)
# are part of the image contract (otherwise ARG is used).
# GEOSX use them so consider modifying their names with care.
#
# The installation directory is provided as a docker build argument.
# We forward it using an environment variable.
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# The same distribution and Dockerfile can be used for various versions of the GNU compilers.
# The GCC_MAJOR_VERSION argument is here to parametrise (--build-arg) the build from the `docker build` command line.
# Note that docker seems to forget about the ARGs after each FROM statement.
# This is why we repeat it below.
ARG GCC_MAJOR_VERSION

# Do not apt-get upgrade (ask the maintainer if you really think something should be upgraded)
RUN apt-get update

# tzdata blocks the installation by interactively asking for the time zone.
# DEBIAN_FRONTEND and TZ variables fix this.
RUN DEBIAN_FRONTEND=noninteractive TZ=America/Los_Angeles \
    apt-get install -y --no-install-recommends \
# gfortran 8, 9 and 10 depend on libgfortran5.
    gcc-$GCC_MAJOR_VERSION \
    g++-$GCC_MAJOR_VERSION \
    libgfortran5 \
# Several scientific (or close) libraries.
# Note the difference between runtime and development packages.
    ca-certificates \
    curl \
    libtbb-dev \
    libblas-dev \
    liblapack-dev \
    zlib1g-dev \
    openmpi-bin \
    libopenmpi-dev \
# Some of the TPL's make "extensive" use of python in their build.
# And we want to test GEOS's python configuration script.
# Unfortunately argparse (standard library's package used by GEOSX)
# is not in the python-minimal package so we install the whole std lib.
    python3

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

ENV CC=/usr/bin/gcc-$GCC_MAJOR_VERSION \
    CXX=/usr/bin/g++-$GCC_MAJOR_VERSION \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIEXEC=/usr/bin/mpirun
# The multi-line definition of arguments does not seem happy
# when a variable uses the value of another variable previously defined on the same line.
ENV OMPI_CC=$CC \
    OMPI_CXX=$CXX

# This stage is dedicated to TPLs uniquely.
# A multi-stage build patern will allow to extract what we need for the GEOS build.
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

# This is the version from the `docker build` command line.
# It is repeated because docker forgets about the ARGs after FROM statements.
ARG GCC_MAJOR_VERSION

ENV FC=/usr/bin/gfortran-$GCC_MAJOR_VERSION \
    MPIFC=/usr/bin/mpifort
# Again, troublesome multi-line definition.
ENV OMPI_FC=$FC

RUN apt-get install -y --no-install-recommends \
    libtbb-dev \
    gfortran-$GCC_MAJOR_VERSION \
    make \
    bc \
    file \
    bison \
    flex \
    patch

# Get host config file from docker build arguments
ARG HOST_CONFIG

# We now configure the build...
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/configure-tpl.sh
# ... before we compile the TPLs!
WORKDIR $BLD_DIR
RUN --mount=src=.,dst=$SRC_DIR make

# Last step is setting everything for a complete slave that will build GEOSX.
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

# I extract the deployed TPLs from the TPL building stqge.
COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Any tool specific to building GEOSX shall be installed in this stage.
RUN apt-get install -y --no-install-recommends \
    openssh-client \
# `ca-certificates` is needed by `sccache` to download the cached compilations.
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

# Install `sccache` binaries to speed up the build of `geos`
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
