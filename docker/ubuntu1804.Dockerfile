# Defining the building toolchain that are common to both GEOSX and its TPLs.
FROM ubuntu:18.04 AS tpl_toolchain_intersect_geosx_toolchain

# FIXME FROM resets the ARGs
# FIXME maybe not if from the command line
ENV GCC_MAJOR_VERSION=8 \
    GEOSX_TPL_DIR=/opt/GEOSX_TPL

# Do not apt-get upgrade (ask thre maintainer if you really think so;ething should be upgraded)
RUN apt-get update

# ca-certificates is necessary to perform https clones
RUN apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    git-lfs \
    cmake \
    make

RUN apt-get install -y --no-install-recommends \
    libtbb2 \
    libblas-dev \
    liblapack-dev \
    zlib1g-dev

# It appears that gfortran-8 depends on ligfortran5 while gfortran-7 depends on libgfortran4
# The $(($GCC_MAJOR_VERSION-3)) is a small bash hack needed to install the runtime library separately.
RUN apt-get install -y --no-install-recommends \
    gcc-${GCC_MAJOR_VERSION} \
    g++-${GCC_MAJOR_VERSION} \
    libgfortran$(($GCC_MAJOR_VERSION-3))

# FIXME F77 F90 are not needed... sure ?

# FIXME utile ? Ou ?
# RUN apt-get install -y --no-install-recommends \
#     openssh-client \
#     openssh-server


# FIXME make another MPI choice?
RUN apt-get -y --no-install-recommends install \
    openmpi-bin \
    libopenmpi-dev
# FIXME libopenmi3 tout court ?

# Some of the TPL's make "extensive" use of python in their build.
# And we want to test GEOSX's python configuration script.
# Unfortunately argparse (standard library's package used by GEOSX)
# is not in the python-minimal package so we install the whole std lib.
RUN apt-get install -y --no-install-recommends \
    python

# FIXME Why original was relative and/or absolute path?
ENV CC=gcc-${GCC_MAJOR_VERSION} \
    CXX=g++-${GCC_MAJOR_VERSION} \
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

ENV FC=gfortran-${GCC_MAJOR_VERSION} \
    MPIFC=/usr/bin/mpifort
# Again, troublesome multi-line definition.
ENV OMPI_FC=$FC

# FIXME desintaller a la main en plus au cas ou on aurait des triggers ? pas sur.
# FIXME: verifier qu,on a un link de qualite...
RUN apt-get install -y --no-install-recommends \
    libtbb-dev \
    gfortran-${GCC_MAJOR_VERSION} \
    bison \
    flex

# FIXME la branche TRAVIS_PULL_REQUEST_BRANCH?

# FIXME WRONG!
# ARG GIT_USER
# ARG GIT_PASSWORD

# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ARG TPL_BUILD_DIR=${TMP_DIR}/build

# FIXME --shallow --branch --single-branch etc.
# FIXME git lfs clone is deprecated
RUN git lfs clone --recurse-submodules https://${GIT_USER}:${GIT_PASSWORD}@github.com/GEOSX/thirdPartyLibs.git ${TPL_SRC_DIR}

#WORKDIR ${TPL_SRC_DIR}
#RUN git --git-dir=thirdPartyLibs lfs install && git --git-dir=thirdPartyLibs submodule init && git --git-dir=thirdPartyLibs submodule update
#RUN git lfs install && git submodule init && git submodule update
# Condfiguring the build...
RUN python ${TPL_SRC_DIR}/scripts/config-build.py \
    --hostconfig ${TPL_SRC_DIR}/host-configs/environment.cmake \
    --buildtype Release \
    --buildpath ${TPL_BUILD_DIR} \
    --installpath ${GEOSX_TPL_DIR}
# ... before the compilation of the TPLs.
WORKDIR ${TPL_BUILD_DIR}
RUN make

# Last step is setting everything for a complete slave for building GEOSX.
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

# I extract the deployed TPLs from the TPL building stqge.
COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

# Any tool specific to building GEOSX shall be installed in this stage.

# FIXME the following lines must not be in the TPL build...
# ARG GEOSX_SRC_DIR=/tmp/GEOSX
# ARG GEOSX_BUILD_DIR=/tmp/build
# WORKDIR $GEOSX_SRC_DIR
# RUN git clone https://${GIT_USER}:${GIT_PASSWORD}@github.com/GEOSX/GEOSX.git .
# RUN git lfs install && git submodule init && git submodule update
# # FIXME temporary
# COPY environment.cmake host-configs/
#
# RUN python scripts/config-build.py -hc host-configs/environment.cmake -bt Release \
#     -bp $GEOSX_BUILD_DIR -DGEOSX_TPL_DIR=$GEOSX_TPL_DIR
# WORKDIR $GEOSX_BUILD_DIR
# RUN make