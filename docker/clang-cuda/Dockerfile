ARG TMP_DIR=/tmp
FROM nvidia/cuda:10.1-devel-ubuntu18.04 AS tpl_toolchain_intersect_geosx_toolchain

ENV GEOSX_TPL_DIR=/opt/GEOSX_TPL

# Installing dependencies
RUN rm /etc/apt/sources.list.d/*.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \ 
    wget \
    gfortran \
    libtbb2 \
    libblas-dev \
    liblapack-dev \
    zlib1g-dev \
    openmpi-bin \
    libopenmpi-dev \
    python

# Newer CMake versions have gfortran errors, downgrading to 3.9
ARG TMP_DIR
ADD https://cmake.org/files/v3.9/cmake-3.9.2-Linux-x86_64.tar.gz ${TMP_DIR}/
RUN tar --directory=/usr/local --strip-components=1 -xzf ${TMP_DIR}/cmake-3.9.2-Linux-x86_64.tar.gz && \
    rm ${TMP_DIR}/cmake-3.9.2-Linux-x86_64.tar.gz

#  Installing clang
ENV llvmtar=clang+llvm-8.0.0-x86_64-linux-gnu-ubuntu-18.04
ENV tarext=.tar.xz
RUN \
       wget -q --no-check-certificate http://releases.llvm.org/8.0.0/${llvmtar}${tarext} \
    && tar xf ${llvmtar}${tarext} \
    && cp -fR ${llvmtar}/* /usr \
    && rm -rf ${llvmtar} \
    && rm ${llvmtar}${tarext}

ENV CC=/usr/bin/clang \
    CXX=/usr/bin/clang++ \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIEXEC=/usr/bin/mpirun
ENV OMPI_CC=${CC} \
    OMPI_CXX=${CXX} 

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

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh --hostconfig ${TPL_SRC_DIR}/host-configs/cuda-environment.cmake
WORKDIR ${TPL_BUILD_DIR}
RUN make

# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

RUN apt-get install -y --no-install-recommends \
    openssh-client \
    texlive \
    graphviz
