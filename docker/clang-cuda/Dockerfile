ARG TMP_DIR=/tmp
FROM nvidia/cuda:10.1-devel-ubuntu18.04 AS tpl_toolchain_intersect_geosx_toolchain

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

# Installing dependencies
RUN rm /etc/apt/sources.list.d/*.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \ 
    curl \
    gfortran \
    libtbb2 \
    libblas-dev \
    liblapack-dev \
    zlib1g-dev \
    openmpi-bin \
    libopenmpi-dev \
    python

# Installing latest CMake version available on Lassen
ARG CMAKE_VERSION=3.14.5
RUN curl -s https://cmake.org/files/v${CMAKE_VERSION%.[0-9]*}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz | tar --directory=/usr/local --strip-components=1 -xzf -

# Installing clang
RUN curl -fsSL http://releases.llvm.org/8.0.0/clang+llvm-8.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz | tar --directory=/usr/local --strip-components=1 -xJf -

ENV CC=/usr/local/bin/clang \
    CXX=/usr/local/bin/clang++ \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIEXEC=/usr/bin/mpirun
ENV OMPI_CC=${CC} \
    OMPI_CXX=${CXX} 
ENV ENABLE_CUDA=ON \
    CMAKE_CUDA_FLAGS="-restrict -arch sm_70 --expt-extended-lambda -Werror cross-execution-space-call,reorder,deprecated-declarations"

# Installing TPL's
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

ENV FC=/usr/bin/gfortran \
    MPIFC=/usr/bin/mpifort
ENV OMPI_FC=${FC}

RUN apt-get install -y --no-install-recommends \
    libtbb-dev \
    bc \
    file \
    bison \
    flex \
    patch

ARG TMP_DIR
ARG TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ARG TPL_BUILD_DIR=${TMP_DIR}/build

ARG HOST_CONFIG

ARG CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda
ARG CUDA_ARCH=sm_70
ARG CMAKE_CUDA_COMPILER=${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc

ENV HYPRE_CUDA_SM=70
ENV CUDA_HOME=${CUDA_TOOLKIT_ROOT_DIR}

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh \
    -DENABLE_CUDA=${ENABLE_CUDA} \
    -DENABLE_HYPRE_CUDA=${ENABLE_CUDA} \
    -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR} \
    -DCUDA_ARCH=${CUDA_ARCH} \
    -DCMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
WORKDIR ${TPL_BUILD_DIR}
RUN make

# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

RUN apt-get install -y --no-install-recommends \
    openssh-client \
    texlive \
    graphviz
