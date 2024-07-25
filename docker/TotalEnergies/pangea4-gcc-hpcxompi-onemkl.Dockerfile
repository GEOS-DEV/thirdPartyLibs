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
#   - the image is based on onetechssc/pangea4:gcc12.1_v1.0 built from pangea4-gcc.Dockerfile
#   - this image is deployed as onetechssc/pangea4:gcc12.1-hpcx2.17.1-onemkl2023.2.0_v1.0
#   - oneAPI MKL is installed via spack (as done for Pangea 4)
#   - hpcx is installed by extracting the tarball (as done for Pangea 4)
#   - gcc wrappers are created to mimic the Cray environment (cc, CC, ftn)
#
#######################################

# -------------------------------------
# PANGEA4 - GCC-HPCX-MKL
FROM onetechssc/pangea4:gcc12.1_v1.0 AS pangea4
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
RUN spack load wget && \
    wget $HPCX_URL -O /tmp/$HPCX_TARBALL
RUN tar -xvf /tmp/$HPCX_TARBALL -C /sw
ENV HPCX_HOME=/sw/$HPCX_VERSION
# ------
# ENV
# - wrappers for gcc
RUN <<EOF cat > /root/set_env.sh
#!/bin/bash
spack load gcc@$GCC_VERSION python@$PYTHON_VERSION cmake@$CMAKE_VERSION intel-oneapi-mkl@$ONEAPI_MKL_VERSION
GCC_INSTALL_DIR=\$(spack location -i gcc@$GCC_VERSION)
export GCC_INSTALL_DIR=\$GCC_INSTALL_DIR
export CC=\${GCC_INSTALL_DIR}/bin/gcc
export CXX=\${GCC_INSTALL_DIR}/bin/g++
export FC=\${GCC_INSTALL_DIR}/bin/gfortran
EOF
RUN chmod +x /root/set_env.sh