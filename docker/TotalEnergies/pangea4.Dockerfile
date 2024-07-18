#######################################
# Pangea 4 image : gcc - hpcxompi - onemkl
#######################################
#
# Installs :
#   - gcc                  = 12.1
#   - hpcx                 = 2.17.1
#   - intel-oneapi-mkl     = 2023.2.0
#   - cmake                = 3.27.9
#   - python               = 3.11
#
#######################################
#
# Description :
#   - the image is based on spack/centos-stream:latest (CentOS Stream 8 image with spack installed)
#   - gcc, hpcx, oneAPI MKL, cmake and python are installed via spack (as done for Pangea 4)
#   - hpcx is installed by extracting the tarball (as done for Pangea 4)
#   - gcc wrappers are created to mimic the Cray environment (cc, CC, ftn)
#
#######################################

# -------------------------------------
# PANGEA4 - BASE [GCC - CMAKE - PYTHON]
# install tools via spack for linux/x86_64 architecture and redhat8 platform
FROM --platform=linux/x86_64 spack/centos-stream:latest AS pangea4-base
# ------
# LABELS
LABEL description="Pangea 4 image : gcc - cmake - python"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG GCC_VERSION=12.1
ARG CMAKE_VERSION=3.27.9
ARG PYTHON_VERSION=3.11
# ------
# INSTALL
# gcc
RUN spack install gcc@$GCC_VERSION
RUN . /opt/spack/share/spack/setup-env.sh &&\
    spack load gcc@$GCC_VERSION &&\
    spack compiler find
# python
RUN spack install python@$PYTHON_VERSION %gcc@$GCC_VERSION
# show compilers
RUN spack compilers
# cmake
RUN spack install cmake@$CMAKE_VERSION %gcc@$GCC_VERSION

# -------------------------------------
# PANGEA4 - GCC-HPCX-MKL [GCC - CMAKE - PYTHON - HPCX - ONEAPI-MKL]
FROM pangea4-base AS pangea4-gcc-hpcx-mkl
# ------
# LABELS
LABEL description="Pangea 4 image : gcc - cmake - python - hpcx - mkl"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG ONEAPI_MKL_VERSION=2023.2.0
ARG HPCX_VERSION="hpcx-v2.17.1-gcc-mlnx_ofed-redhat8-cuda12-x86_64"
ARG HPCX_TARBALL="$HPCX_VERSION.tbz"
ARG HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v2.17.1/$HPCX_TARBALL"
# ------
# INSTALL
# intel-oneapi-mkl
RUN spack install intel-oneapi-mkl@$ONEAPI_MKL_VERSION %gcc@$GCC_VERSION
# hpcx not available in spack -> download and untar (untar in /sw directory)
RUN mkdir -p /sw
RUN wget $HPCX_URL -O /tmp/$HPCX_TARBALL
RUN tar -xvf /tmp/$HPCX_TARBALL -C /sw
ENV HPCX_HOME=/sw/$HPCX_VERSION
# ------
# ENV
# - create spack env
RUN spack env activate --create -p prgenv && \
    spack add gcc@$GCC_VERSION python@$PYTHON_VERSION cmake@$CMAKE_VERSION intel-oneapi-mkl@$ONEAPI_MKL_VERSION
# - wrappers for gcc
RUN spack env activate prgenv && export GCC_INSTALL_DIR=$(spack location -i gcc@$GCC_VERSION)
ENV CC=${GCC_INSTALL_DIR}/bin/gcc \
    CXX=${GCC_INSTALL_DIR}/bin/g++ \
    FC=${GCC_INSTALL_DIR}/bin/gfortran
