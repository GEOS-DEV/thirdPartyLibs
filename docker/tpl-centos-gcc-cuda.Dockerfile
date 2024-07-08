# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp 
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

FROM nvidia/cuda:11.8.0-devel-centos7 AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Add the sed package directly from a URL
ADD http://vault.centos.org/7.9.2009/os/x86_64/Packages/sed-4.2.2-7.el7.x86_64.rpm /tmp/sed.rpm

# Install sed using rpm
RUN rpm -ivh /tmp/sed.rpm && rm -f /tmp/sed.rpm

RUN sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/*.repo \
    sed -i s/^#.*baseurl=http/baseurl=https/g /etc/yum.repos.d/*.repo \
    sed -i s/^mirrorlist=http/#mirrorlist=https/g /etc/yum.repos.d/*.repo 

# Using gcc 8.3.1 provided by the Software Collections (SCL).
RUN yum install -y \
    centos-release-scl \
    && yum install -y \
    devtoolset-8-gcc \
    devtoolset-8-gcc-c++ \
    devtoolset-8-gcc-gfortran

# Installing dependencies
RUN yum -y install \
    ca-certificates \
    curl \
    tbb \
    blas-devel \
    lapack-devel \
    zlib-devel \
    openmpi-devel \
    python3

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

ENV CC=/opt/rh/devtoolset-8/root/usr/bin/gcc \
    CXX=/opt/rh/devtoolset-8/root/usr/bin/g++ \
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

ENV FC=/opt/rh/devtoolset-8/root/usr/bin/gfortran \
    MPIFC=/usr/lib64/openmpi/bin/mpifort
ENV OMPI_FC=$FC

RUN yum install -y \
    tbb-devel \
    make \
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

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/configure-tpl.sh \
    -DENABLE_CUDA=$ENABLE_CUDA \
    -DENABLE_HYPRE_DEVICE="CUDA" \
    -DCUDA_TOOLKIT_ROOT_DIR=$CUDA_TOOLKIT_ROOT_DIR \
    -DCUDA_ARCH=$CUDA_ARCH \
    -DCMAKE_CUDA_ARCHITECTURES=$CMAKE_CUDA_ARCHITECTURES \
    -DCMAKE_CUDA_COMPILER=$CMAKE_CUDA_COMPILER
WORKDIR $BLD_DIR
RUN --mount=src=.,dst=$SRC_DIR make

# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR
RUN yum install -y \
    openssh-client \
    ca-certificates \
    curl \
    python3 \
    texlive \
    graphviz \
    git

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-ninja.sh

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
