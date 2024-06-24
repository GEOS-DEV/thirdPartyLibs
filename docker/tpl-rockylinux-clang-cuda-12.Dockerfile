# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

FROM nvidia/cuda:12.5.0-devel-rockylinux8 AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Installing dependencies
RUN dnf clean all && \
    dnf -y update && \
    dnf -y install \
        which \ 
        clang \ 
        gcc-gfortran \
        python3 \
        zlib-devel \
        tbb \
        blas \
        lapack \
        openmpi \
        openmpi-devel

RUN dnf config-manager --set-enabled  &      
        
# Find the location of mpicc, blas and lapack and add to PATH
RUN MPI_PATH=$(find /usr -name mpicc | head -n 1) && \
    MPI_DIR=$(dirname $MPI_PATH) && \
    BLAS_DIR=$(find / -name "libblas*") && \
    LAPACK_DIR=$(find -name "liblapack*") && \
    echo "MPI binary directory: $MPI_DIR" && \
    echo "Blas directory: $BLAS_DIR" && \
    echo "Lapack directory: $LAPACK_DIR" && \ 
    export PATH=$PATH:$MPI_DIR && \
    export PATH=$PATH:$BLAS_DIR && \
    export PATH=$PATH:$LAPACK_DIR && \
    echo $PATH 

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

ENV CC=/usr/bin/clang \
    CXX=/usr/bin/clang++ \
    MPICC=/usr/lib64/openmpi/bin/mpicc \
    MPICXX=/usr/lib64/openmpi/bin/mpicxx \
    MPIEXEC=/usr/lib64/openmpi/bin/mpirun 

ENV OMPI_CC=$CC \
    OMPI_CXX=$CXX

ENV ENABLE_CUDA=ON \
    CMAKE_CUDA_FLAGS="-restrict -arch sm_70 --expt-extended-lambda -Werror cross-execution-space-call,reorder,deprecated-declarations"

# Installing TPL's
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

ENV FC=/usr/bin/gfortran \
    MPIFC=/usr/lib64/openmpi/bin/mpifort
ENV OMPI_FC=$FC

# Install required packages using dnf
RUN dnf clean all && \
    dnf -y update && \
    dnf -y install \
        tbb-devel \
        bc \
        file \
        bison \
        flex \
        patch

ARG HOST_CONFIG

ARG CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda
ARG CUDA_ARCH=sm_70
ARG CMAKE_CUDA_COMPILER=$CUDA_TOOLKIT_ROOT_DIR/bin/nvcc
ARG CMAKE_CUDA_ARCHITECTURES=70

ENV HYPRE_CUDA_SM=70
ENV CUDA_HOME=$CUDA_TOOLKIT_ROOT_DIR

# Run the configuration script
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/configure-tpl.sh \
    -DENABLE_CUDA=$ENABLE_CUDA \
    -DENABLE_HYPRE_DEVICE="CUDA" \
    -DCUDA_TOOLKIT_ROOT_DIR=$CUDA_TOOLKIT_ROOT_DIR \
    -DCUDA_ARCH=$CUDA_ARCH \
    -DCMAKE_CUDA_ARCHITECTURES=$CMAKE_CUDA_ARCHITECTURES \
    -DCMAKE_CUDA_COMPILER=$CMAKE_CUDA_COMPILER \
    -DBLAS_LIBRARIES="/usr/lib64/libblas.so.3.8.0" \
    -DLAPACK_LIBRARIES="/usr/lib64/liblapack.so.3.8.0"

# Set the working directory
WORKDIR $BLD_DIR

# Build the project
RUN --mount=src=.,dst=$SRC_DIR make

# Extract only TPL's from the previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Install required packages using dnf
RUN dnf clean all && \
    rm -rf /var/cache/dnf && \
    dnf -y install dnf-plugins-core && \
    dnf config-manager --set-enabled devel && \
    dnf -y update && \
    dnf -y install \
        openssh-clients \
        ca-certificates \
        curl \
        python3 \
        texlive \
        graphviz \
        ninja-build

# Run the installation script
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
