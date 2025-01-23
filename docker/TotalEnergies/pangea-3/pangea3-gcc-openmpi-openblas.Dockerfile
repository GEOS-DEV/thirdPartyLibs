# syntax=docker/dockerfile:1

#######################################
# Pangea 3 image : gcc - openmpi - openblas
#######################################
#
# Installs :
#   - gcc      = 11.4.0
#   - cmake    = 3.27.9
#   - openmpi  = 4.1.6
#   - openblas = 0.3.18
#   - cuda     = 11.8.0
#
#######################################
#
# Description :
#   - this Dockerfile is used to build a docker image reproducing the Pangea-3 installation over a ppc64le architecture:
#   - it is not directly callable by the TPL ci but the built image is.
#   - the image is based on ppc64le/almalinux:8
#   - this image is deployed as onetechssc/pangea3:almalinux8-gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0
#   - gcc, cmake, openmpi, openblas and cuda are copied from the tarball directory of Pangea 3
#
# Usage :
#   build the image:
#   - copy the tarball directory from the Pangea 3 repository to the current directory
#   - podman build -f pangea3-gcc-openmpi-openblas.Dockerfile -t onetechssc/pangea3:almalinux8-gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0 -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem/
#   run the image:
#   - podman run -it --detach --privileged --name pangea3_gcc_ompi_oblas -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem localhost/onetechssc/pangea3:almalinux8-gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0
#   - podman exec -it pangea3_gcc_ompi_oblas /bin/bash
#   push the image (requires to be part of the onetechssc docker organization):
#   - podman login docker.io
#   - podman push pangea3:almalinux8-gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0 docker://docker.io/onetechssc/pangea3:almalinux8-gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0
#
#######################################

FROM ppc64le/almalinux:8 AS pangea3

# ------
# LABELS
LABEL description="Pangea 3 image : gcc - cmake - openmpi - openblas - cuda"
LABEL version="2.0"
LABEL maintainer="TotalEnergies HPC Team"

# ------
# INSTALL BASE PACKAGES
RUN dnf install -y \
    # gcc deps \
    libmpc-devel.ppc64le glibc-devel \
    # mpirun deps  \
    librdmacm hwloc \
    git git-lfs \
    python38-devel python38-numpy \
    zlib-devel \
    make \
    bc \
    file \
    # Scotch deps \
    bison \
    flex \
    # vtk deps \
    patch && \
    git-lfs install #&& alternatives --set python /usr/bin/python3

# copy pangea tree for modules needed by TPLs and export environment variables

## Temporary local variables needed buy several modules
ARG MODULE_PATH="/data_local/sw"
ARG SPACK_PATH="spack/0.22.1/opt/spack/linux-rhel8-power9le"

ARG COMPILER="gcc"
ARG DEFAULT_COMPILER_VER="8.4.1"
ARG SPACK_COMPILER_VER=$DEFAULT_COMPILER_VER
ARG MODULE_COMPILER_VER="11.4.0"

ARG SPACK_COMPILER=$COMPILER-$SPACK_COMPILER_VER

## liblustre
COPY ./tarball/liblustreapi.so.1 /lib64/

# ------
# CMAKE
ADD ./tarball/cmake-*.tgz /

### Environment variables to export
ENV PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/cmake-3.27.9-yfuovjb3tx73ymsxuw5hoxv3eqdchned/bin:${PATH}"

# ------
# GCC
ADD ./tarball/gcc-*.tgz /

### Temporary local variables
ARG GCC_VER=$COMPILER-$MODULE_COMPILER_VER
ARG GCC_DIR="$GCC_VER-bbeypfg5smd3pgbsdswprcja7cxdxyqn"

### Environment variables to export
ENV CPATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR/include:${CPATH}" \
    LD_LIBRARY_PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR/lib:\
$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR/lib64:${LD_LIBRARY_PATH}" \
    LD_RUN_PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR/lib:\
$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR/lib64:${LD_RUN_PATH}" \
    MANPATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR/share/man:${MANPATH}" \
    PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR/bin:${PATH}" \
    CC=gcc \
    CXX=g++ \
    F77=gfortran \
    F90=gfortran \
    FC=gfortran \
    GCC_ROOT=$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$GCC_DIR

# ------
# OMPI
ADD ./tarball/ompi-*.tgz /

### Temporary local variables
ARG MPI_VER="4.1.6"
ARG MPI_DIR="openmpi/$MPI_VER"
ARG MPI_PREFIX="OMPI"

### Environment variables to export
ENV CPATH="$MODULE_PATH/$MPI_DIR/env/$SPACK_COMPILER/include:${CPATH}" \
    LD_LIBRARY_PATH="$MODULE_PATH/$MPI_DIR/env/$SPACK_COMPILER/lib:${LD_LIBRARY_PATH}" \
    MANPATH="$MODULE_PATH/$MPI_DIR/env/$SPACK_COMPILER/share/man:${MANPATH}" \
    PATH="$MODULE_PATH/$MPI_DIR/env/$SPACK_COMPILER/bin:${PATH}" \
    MPI_ROOT="$MODULE_PATH/$MPI_DIR/env/$SPACK_COMPILER" \
    ${MPI_PREFIX}_CC="gcc" \
    ${MPI_PREFIX}_CXX="g++" \
    ${MPI_PREFIX}_F77="gfortran" \
    ${MPI_PREFIX}_F90="gfortran" \
    ${MPI_PREFIX}_FC="gfortran" \
    OPAL_PREFIX="$MODULE_PATH/$MPI_DIR/env/$SPACK_COMPILER" \
    OMPI_MCA_btl="self,vader,openib" \
    OMPI_MCA_btl_openib_allow_ib="true" \
    OMPI_MCA_btl_openib_warn_default_gid_prefix="0"

# ------
# CUDA
ADD ./tarball/cuda-*.tgz /

### Temporary local variables
ARG LIBCUDA_VER=450.156.00

ARG CUDA_VER_MAJ="11"
ARG CUDA_VER_MIN="8"
ARG CUDA_VER_PATCH="0"
ARG CUDA_VER="$CUDA_VER_MAJ.$CUDA_VER_MIN.$CUDA_VER_PATCH"
ARG CUDA_DIR="cuda/$CUDA_VER"

ARG CUPTI_DIR="$CUDA_DIR/extras/CUPTI"

COPY ./tarball/libcuda.so.$LIBCUDA_VER /usr/lib64
RUN ln -s /usr/lib64/libcuda.so.$LIBCUDA_VER /usr/lib64/libcuda.so.1

### Environment variables to export
ENV CPATH="$MODULE_PATH/$CUDA_DIR/include:\
$MODULE_PATH/$CUPTI_DIR/include:${CPATH}" \
    LIBRARY_PATH="$MODULE_PATH/$CUDA_DIR/lib64/stubs:\
$MODULE_PATH/$CUDA_DIR/lib64:\
$MODULE_PATH/$CUPTI_DIR/lib64:${LIBRARY_PATH}" \
    LD_LIBRARY_PATH="$MODULE_PATH/$CUDA_DIR/lib64:\
$MODULE_PATH/$CUPTI_DIR/lib64:${LD_LIBRARY_PATH}" \
    LD_RUN_PATH="$MODULE_PATH/$CUDA_DIR/lib64:${LD_RUN_PATH}" \
    MANPATH="$MODULE_PATH/$CUDA_DIR/doc/man:${MANPATH}" \
    PATH="$MODULE_PATH/$CUDA_DIR/bin:\
$MODULE_PATH/$CUDA_DIR/samples/bin/ppc64le/linux/release:${PATH}" \
    CUBLAS_ROOT="$MODULE_PATH/$CUDA_DIR" \
    CUDA_ROOT="$MODULE_PATH/$CUDA_DIR" \
    CUDA_HOME="$MODULE_PATH/$CUDA_DIR" \
    CUDA_PATH="$MODULE_PATH/$CUDA_DIR" \
    CUDA_VERSION="$CUDA_VER_MAJ.$CUDA_VER_MIN" \
    NVHPC_CUDA_HOME="$MODULE_PATH/$CUDA_DIR"

# ------
# OPENBLAS
ADD ./tarball/openblas-*.tgz /

### Temporary local variables
ARG SPACK_COMPILER=$COMPILER-$MODULE_COMPILER_VER

ARG BLAS_VER_MAJ="0"
ARG BLAS_VER_MIN="3"
ARG BLAS_VER_PATCH="18"
ARG BLAS_DISTRIB="openblas"
ARG BLAS_VER="$BLAS_VER_MAJ.$BLAS_VER_MIN.$BLAS_VER_PATCH"
ARG BLAS_DIR="$BLAS_DISTRIB-$BLAS_VER-cing5yuan7hsn23qmeemon4zwih3k2hd"

### Environment variables to export
ENV LD_LIBRARY_PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR/lib:${LD_LIBRARY_PATH}" \
    LIBRARY_PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR/lib:${LIBRARY_PATH}" \
    PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR/bin:${PATH}" \
    OPENBLAS_ROOT="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR"

# ------
# LSF
ADD ./tarball/lsf-*.tgz /

### Temporary local variables
ARG GLIBC_DIR="linux3.10-glibc2.17-ppc64le"

ARG LSF_VER_MAJ="10"
ARG LSF_VER_MIN="1"
ARG LSF_VER="$LSF_VER_MAJ.$LSF_VER_MIN"
ARG LSF_DIR="lsf/$LSF_VER/$GLIBC_DIR"

### Environment variables to export
ENV LD_LIBRARY_PATH="$MODULE_PATH/$LSF_DIR/lib:${LD_LIBRARY_PATH}" \
    PATH="$MODULE_PATH/$LSF_DIR/etc:$MODULE_PATH/$LSF_DIR/bin:${PATH}"

# Uncomment the two following lines to test the TPLs build
#
#WORKDIR /root
#RUN git clone --depth=1  https://github.com/GEOS-DEV/thirdPartyLibs.git && \
#    cd thirdPartyLibs && git submodule init && git submodule update

#RUN cd thirdPartyLibs && python3 scripts/config-build.py \
#    --hostconfig=host-configs/TOTAL/pangea3-gcc8.4.1-openmpi-4.1.2.cmake \
#    --buildtype=Release --installpath=/opt/tpls -DNUM_PROC=32 && \
#    make -C build-pangea3-gcc8.4.1-openmpi-4.1.2-release -j && \
#    cd .. && rm -rf thirdPartyLibs

# ------
# CI TOOLS
RUN dnf -y --enablerepo=powertools install \
    ninja-build \
    openssh-clients \
    texlive \
    graphviz \
    libxml2

# build sccache from source as prebuilt binary is not available for current archi / OS couple
RUN dnf clean all && dnf makecache --refresh && dnf -y install cargo openssl-devel
RUN cargo install sccache --locked && mkdir -p /opt/sccache/ && cp -r /root/.cargo/bin /opt/sccache/
RUN dnf remove -y cargo openssl-devel

### Environment variables to export
ENV SCCACHE=/opt/sccache/bin/sccache
