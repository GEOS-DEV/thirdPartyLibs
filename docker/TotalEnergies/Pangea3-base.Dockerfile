# This Dockerfile is used to build a docker image reproducing the Pangea installation over a ppc64le architecture:
# It is not directly callable by the TPL ci but the built image is.

# syntax=docker/dockerfile:1
FROM ppc64le/almalinux:8

# Install other needed packages
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
    # vtk deps \
    patch && \
    git-lfs install #&& alternatives --set python /usr/bin/python3

# copy pangea tree for modules needed by TPLs and export environment variables

## Temporary local variables needed buy several modules
ARG MODULE_PATH="/data_local/sw"

ARG SPACK_PATH="spack/0.17.0/opt/spack/linux-rhel8-power9le"

ARG COMPILER="gcc"
ARG DEFAULT_COMPILER_VER="8.4.1"
ARG SPACK_COMPILER_VER=$DEFAULT_COMPILER_VER
ARG MODULE_COMPILER_VER="9.4.0"

ARG SPACK_COMPILER=$COMPILER-$SPACK_COMPILER_VER

## liblustre
COPY ./tarball/liblustreapi.so.1 /lib64/

## CMake
ADD ./tarball/cmake-*.tgz /

### Environment variables to export
ENV PATH="/data_local/appli_local/MTS/GEOSX/cmake/3.26.4/bin:${PATH}"

## gcc
ADD ./tarball/gcc-*.tgz /

### Temporary local variables
ARG GCC_VER=$COMPILER-$MODULE_COMPILER_VER
ARG GCC_DIR="$GCC_VER-xe5cqnyajaqz75up3gflln5zlj2rue5v"

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

## ompi
ADD ./tarball/ompi-*.tgz /

### Temporary local variables
ARG MPI_VER="4.1.2"
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

## Cuda
ADD ./tarball/cuda-*.tgz /

### Temporary local variables
ARG LIBCUDA_VER=450.156.00

ARG CUDA_VER_MAJ="11"
ARG CUDA_VER_MIN="5"
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

## Openblas
ADD ./tarball/openblas-*.tgz /

### Temporary local variables
ARG SPACK_COMPILER=$COMPILER-$MODULE_COMPILER_VER

ARG BLAS_VER_MAJ="0"
ARG BLAS_VER_MIN="3"
ARG BLAS_VER_PATCH="18"
ARG BLAS_DISTRIB="openblas"
ARG BLAS_VER="$BLAS_VER_MAJ.$BLAS_VER_MIN.$BLAS_VER_PATCH"
ARG BLAS_DIR="$BLAS_DISTRIB-$BLAS_VER-vk36pzksytuhylqesg4cca7667np5sjp"

### Environment variables to export
ENV LD_LIBRARY_PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR/lib:${LD_LIBRARY_PATH}" \
    LIBRARY_PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR/lib:${LIBRARY_PATH}" \
    PATH="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR/bin:${PATH}" \
    OPENBLAS_ROOT="$MODULE_PATH/$SPACK_PATH/$SPACK_COMPILER/$BLAS_DIR"

## lsf
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

# Install tools needed by geos ci
RUN dnf -y --enablerepo=powertools install \
    ninja-build \
    openssh-clients \
    texlive \
    graphviz \
    libxml2

# build sccache from source as prebuilt binary is not available for current archi / OS couple
RUN dnf makecache --refresh && dnf -y install cargo openssl-devel
RUN cargo install sccache --locked && mkdir -p /opt/sccache/ && cp -r /root/.cargo/bin /opt/sccache/
RUN dnf remove -y cargo openssl-devel

### Environment variables to export
ENV SCCACHE=/opt/sccache/bin/sccache
