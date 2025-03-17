#######################################
# Pangea 4 image : gcc - hpcxompi - onemkl
#######################################
#
# Installs :
#   - hpcx             = 2.20.0
#   - intel-oneapi-mkl = 2023.2.0
#
#######################################
#
# Description :
#   - the image is based on onetechssc/pangea4:gcc12.1_v1.0 built from pangea4-gcc.Dockerfile
#   - this image is deployed as onetechssc/pangea4:gcc12.1-hpcx2.20.0-onemkl2023.2.0_v1.0
#   - oneAPI MKL is installed via spack (as done for Pangea 4)
#   - hpcx is installed by extracting the tarball (as done for Pangea 4)
#   - gcc wrappers are created to mimic the Cray environment (cc, CC, ftn)
#
# Usage :
#   build the image:
#   - podman build --format docker -t onetechssc/pangea4:gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0 -f pangea4-gcc-hpcxompi-onemkl.Dockerfile -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem  .
#   run the image:
#   - podman run -it --detach --privileged --name pangea4_gcc_hpcxompi_onemkl -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem localhost/onetechssc/pangea4:gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0
#   - podman exec -it pangea4_gcc_hpcxompi_onemkl /bin/bash
#   push the image (requires to be part of the onetechssc docker organization):
#   - podman login docker.io
#   - podman push localhost/onetechssc/pangea4:gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0 docker://docker.io/onetechssc/pangea4:gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0
#
#######################################

# -------------------------------------
# PANGEA4 - GCC-HPCX-MKL
FROM docker.io/onetechssc/pangea4:gcc12.1_v1.0 AS pangea4
# ------
# LABELS
LABEL description="Pangea 4 image : gcc - cmake - python - hpcx - mkl"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG ONEAPI_MKL_VERSION=2023.2.0
ARG HPCX_VERSION=2.20
ARG HPCX_FULL_NAME="hpcx-v$HPCX_VERSION-gcc-mlnx_ofed-redhat8-cuda12-x86_64"
ARG HPCX_TARBALL="$HPCX_FULL_NAME.tbz"
ARG HPCX_URL="http://www.mellanox.com/downloads/hpc/hpc-x/v$HPCX_VERSION/$HPCX_TARBALL"
ARG CRAY_WRAPPERS_DIR=/sw/cray-wrappers
# ------
# INSTALL
# spack config (make sure you survive our wonderfull proxy)
RUN spack config --scope defaults add config:connect_timeout:120
RUN spack config --scope defaults add config:url_fetch_method:curl
# intel-oneapi-mkl
RUN spack install intel-oneapi-mkl@$ONEAPI_MKL_VERSION %gcc@$GCC_VERSION
# hpcx not available in spack -> download and untar in /sw directory
RUN mkdir -p /sw && \
    spack load wget && \
    wget --ca-certificate=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem $HPCX_URL -O /tmp/$HPCX_TARBALL && \
    tar -xvf /tmp/$HPCX_TARBALL -C /sw && \
    rm -f /tmp/$HPCX_TARBALL
ENV HPCX_HOME=/sw/$HPCX_FULL_NAME
# numpy with mkl
RUN spack install py-numpy %gcc@$GCC_VERSION ^python@$PYTHON_VERSION ^intel-oneapi-mkl@$ONEAPI_MKL_VERSION
# ------
# ENV
# create wrappers for gcc
RUN mkdir -p $CRAY_WRAPPERS_DIR && \
    spack load gcc@$GCC_VERSION python@$PYTHON_VERSION cmake@$CMAKE_VERSION intel-oneapi-mkl@$ONEAPI_MKL_VERSION && \
    GCC_INSTALL_DIR=$(spack location -i gcc@$GCC_VERSION) && \
    ln -s ${GCC_INSTALL_DIR}/bin/gcc $CRAY_WRAPPERS_DIR/cc && \
    ln -s ${GCC_INSTALL_DIR}/bin/g++ $CRAY_WRAPPERS_DIR/CC && \
    ln -s ${GCC_INSTALL_DIR}/bin/gfortran $CRAY_WRAPPERS_DIR/ftn
# create env script
RUN <<EOF cat > /root/.setup_env.sh
. /opt/spack/share/spack/setup-env.sh
spack load gcc@$GCC_VERSION python@$PYTHON_VERSION cmake@$CMAKE_VERSION intel-oneapi-mkl@$ONEAPI_MKL_VERSION py-numpy
source ${HPCX_HOME}/hpcx-init.sh
hpcx_load
export PATH=$CRAY_WRAPPERS_DIR:\$PATH
export GCC_INSTALL_DIR=$(spack location -i gcc@$GCC_VERSION)
export GOMP_ROOT=\${GCC_INSTALL_DIR}/lib64
EOF
RUN chmod +x /root/.setup_env.sh
