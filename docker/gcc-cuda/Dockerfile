# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp 
ARG TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ARG TPL_BUILD_DIR=${TMP_DIR}/build

FROM nvidia/cuda:11.8.0-devel-centos7 AS tpl_toolchain_intersect_geosx_toolchain

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

# Using gcc 8.3.1 provided by the Software Collections (SCL).
RUN yum install -y \
    centos-release-scl \
    && yum install -y \
    devtoolset-8-gcc \
    devtoolset-8-gcc-c++ \
    devtoolset-8-gcc-gfortran

# Installing dependencies
RUN yum -y install \
    tbb \
    blas-devel \
    lapack-devel \
    zlib-devel \
    openmpi-devel \
    python3

ENV CC=/opt/rh/devtoolset-8/root/usr/bin/gcc \
    CXX=/opt/rh/devtoolset-8/root/usr/bin/g++ \
    MPICC=/usr/lib64/openmpi/bin/mpicc \
    MPICXX=/usr/lib64/openmpi/bin/mpicxx \
    MPIEXEC=/usr/lib64/openmpi/bin/mpirun
ENV OMPI_CC=${CC} \
    OMPI_CXX=${CXX} 
ENV ENABLE_CUDA=ON \
    CMAKE_CUDA_FLAGS="-restrict -arch sm_70 --expt-extended-lambda -Werror cross-execution-space-call,reorder,deprecated-declarations"

# Installing TPL's
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

ENV FC=/opt/rh/devtoolset-8/root/usr/bin/gfortran \
    MPIFC=/usr/lib64/openmpi/bin/mpifort
ENV OMPI_FC=${FC}

RUN yum install -y \
    tbb-devel \
    make \
    bc \
    file \
    bison \
    flex \
    ca-certificates \
    curl \
    patch

ARG HOST_CONFIG

ARG CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda
ARG CUDA_ARCH=sm_70
ARG CMAKE_CUDA_COMPILER=${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc
ARG CMAKE_CUDA_ARCHITECTURES=70

ENV HYPRE_CUDA_SM=70
ENV CUDA_HOME=${CUDA_TOOLKIT_ROOT_DIR}

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/install_cmake.sh
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh \
    -DENABLE_CUDA=${ENABLE_CUDA} \
    -DENABLE_HYPRE_DEVICE="CUDA" \
    -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR} \
    -DCUDA_ARCH=${CUDA_ARCH} \
    -DCMAKE_CUDA_ARCHITECTURES=${CMAKE_CUDA_ARCHITECTURES} \
    -DCMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
WORKDIR ${TPL_BUILD_DIR}
RUN make

# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

RUN yum install -y \
    openssh-client \
    texlive \
    graphviz \
    git

RUN ${TPL_SRC_DIR}/docker/install_ninja.sh

RUN ${TPL_SRC_DIR}/docker/install_sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
