# Defining the building toolchain that are common to both GEOSX and its TPLs.
FROM ubuntu:18.04 AS tpl_toolchain_intersect_geosx_toolchain

# All the environment variables defined in this Dockerfile
# (GEOSX_TPL_DIR but also compiler information like CC, CXX...)
# are part of the image contract (otherwise ARG is used).
# GEOSX use them so consider modifying their names with care.
ENV GEOSX_TPL_DIR=/opt/GEOSX_TPL

# The same distribution and Dockerfile can be used for the 7 and 8 version of the GNU compilers
# The GCC_MAJOR_VERSION argument is here to parametrise (--build-arg) the build from the `docker build` command line.
# Note that docker seems to forget about the ARGs after each FROM statement.
# This is why we repeat it below.
ARG GCC_MAJOR_VERSION

# Do not apt-get upgrade (ask thre maintainer if you really think so;ething should be upgraded)
RUN apt-get update

RUN apt-get install -y --no-install-recommends \
    cmake \
    make \
# It appears that gfortran-8 depends on ligfortran5 while gfortran-7 depends on libgfortran4.
# The $(($GCC_MAJOR_VERSION-3)) is a small bash hack needed to install the runtime library separately.
    gcc-${GCC_MAJOR_VERSION} \
    g++-${GCC_MAJOR_VERSION} \
    libgfortran$((${GCC_MAJOR_VERSION}-3)) \
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

ENV CC=/usr/bin/gcc-${GCC_MAJOR_VERSION} \
    CXX=/usr/bin/g++-${GCC_MAJOR_VERSION} \
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

# This is the version from the `docker build` command line.
# It is repeated because docker seems to forget about the ARGs after FROM statements.
ARG GCC_MAJOR_VERSION

ENV FC=/usr/bin/gfortran-${GCC_MAJOR_VERSION} \
    MPIFC=/usr/bin/mpifort
# Again, troublesome multi-line definition.
ENV OMPI_FC=$FC

RUN apt-get install -y --no-install-recommends \
    libtbb-dev \
    gfortran-${GCC_MAJOR_VERSION} \
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
    openssh-client
