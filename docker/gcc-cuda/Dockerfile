ARG TMP_DIR=/tmp
FROM nvidia/cuda:10.1-devel-ubuntu18.04 AS tpl_toolchain_intersect_geosx_toolchain

ENV GEOSX_TPL_DIR=/opt/GEOSX_TPL

# Installing dependencies
RUN rm /etc/apt/sources.list.d/*.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \ 
    gcc-8 \
    g++-8 \
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
RUN curl -k https://cmake.org/files/v3.14/cmake-3.14.5-Linux-x86_64.tar.gz | tar --directory=/usr/local --strip-components=1 -xzf - 

ENV CC=/usr/bin/gcc-8 \
    CXX=/usr/bin/g++-8 \
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

ARG CUDA_TOOLKIT_ROOT_DIR=/usr/local/cuda
ARG CUDA_ARCH=sm_70
ARG CMAKE_CUDA_COMPILER=${CUDA_TOOLKIT_ROOT_DIR}/bin/nvcc

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh \
    -DENABLE_CUDA=${ENABLE_CUDA} \
    -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_TOOLKIT_ROOT_DIR} \
    -DCUDA_ARCH=${CUDA_ARCH} \
    -DCMAKE_CUDA_COMPILER=${CMAKE_CUDA_COMPILER}
WORKDIR ${TPL_BUILD_DIR}
RUN make

# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    openssh-client \
    texlive \
    graphviz
