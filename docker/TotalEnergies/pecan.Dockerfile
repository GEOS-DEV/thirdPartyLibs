ARG GCC_VERSION=8.2.0
ARG OPENMPI_VERSION=4.0.1
ARG UCX_VERSION=1.3.0
# Note that you need to define both SLURM_TARBALL and SLURM_HOME because one cannot be deduced from the other smoothly.
# It would require (heavy?) text processing for little benefit.
ARG SLURM_TARBALL=slurm-20-02-0-1.tar.gz
ARG SLURM_HOME=/apps/slurm/x86/20.02.0

ARG GCC_HOME=/apps/gcc/${GCC_VERSION}/x86_64
ARG UCX_HOME=/hrtc/apps/devtools/ucx/${UCX_VERSION}/x86_64_nocuda/gcc/${GCC_VERSION}
ARG OPENMPI_HOME=/hrtc/apps/mpi/openmpi/${OPENMPI_VERSION}/RDHPC/gcc/${GCC_VERSION}
# While the installation directory is defined here, the patches and exact versions are still defined in the CUDA stage.
ARG CUDA_HOME=/hrtc/apps/cuda/10.2.89/x86_64

FROM centos:7.7.1908 AS shared_components

RUN yum install -y \
    glibc-devel

FROM shared_components AS gcc_stage

ARG GCC_VERSION
ARG GCC_HOME

# FIXME wget could be replaced by curl in the contrib/download_prerequisites script. To be challenged.
RUN yum install -y \
    make \
    gcc \
    gcc-c++ \
    wget \
    bzip2 \
    zlib-devel

WORKDIR /tmp/src
RUN curl -s https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz | tar --strip-components=1 -xzf -
RUN ./contrib/download_prerequisites
RUN ./configure \
    --prefix=${GCC_HOME} \
    --disable-multilib \
    --with-system-zlib \
    --enable-threads=posix \
    --enable-languages=c,c++,fortran
RUN make -j $(nproc) && make install-strip

FROM shared_components AS ucx_stage

ARG UCX_VERSION
ARG UCX_HOME
ARG GCC_HOME

COPY --from=gcc_stage ${GCC_HOME} ${GCC_HOME}

ENV CC=${GCC_HOME}/bin/gcc \
    CXX=${GCC_HOME}/bin/g++ \
    FC=${GCC_HOME}/bin/gfortran \
    LD_LIBRARY_PATH=${GCC_HOME}/lib64

RUN yum install -y \
    make \
    numactl-devel

WORKDIR /tmp/src
RUN curl -fsSL https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz | tar --strip-components=1 -xzf -
RUN ./configure \
    --prefix=${UCX_HOME} \
    --enable-mt \
    --disable-optimizations \
    --disable-logging \
    --disable-debug \
    --disable-assertions
RUN make -j $(nproc) && make install

FROM shared_components AS slurm_stage

ARG SLURM_TARBALL
ARG SLURM_HOME
ARG GCC_HOME

COPY --from=gcc_stage ${GCC_HOME} ${GCC_HOME}

ENV CC=${GCC_HOME}/bin/gcc \
    CXX=${GCC_HOME}/bin/g++ \
    FC=${GCC_HOME}/bin/gfortran \
    LD_LIBRARY_PATH=${GCC_HOME}/lib64

RUN yum install -y perl python3 file make

WORKDIR /tmp/src
RUN curl -fsSL https://github.com/SchedMD/slurm/archive/${SLURM_TARBALL} | tar --strip-components=1 -xzf -
RUN ./configure --prefix=${SLURM_HOME}
RUN make -j $(nproc) && make install

FROM shared_components AS openmpi_stage

ARG SLURM_HOME
ARG UCX_HOME
ARG GCC_HOME
# FIXME so we do not use SLURM?
ARG OPENMPI_VERSION
ARG OPENMPI_HOME

COPY --from=gcc_stage ${GCC_HOME} ${GCC_HOME}
COPY --from=ucx_stage ${UCX_HOME} ${UCX_HOME}
COPY --from=slurm_stage ${SLURM_HOME} ${SLURM_HOME}

ENV CC=${GCC_HOME}/bin/gcc \
    CXX=${GCC_HOME}/bin/g++ \
    FC=${GCC_HOME}/bin/gfortran \
    LD_LIBRARY_PATH=${GCC_HOME}/lib64

RUN yum install -y \
    perl \
    make \
    zlib-devel \
    numactl-devel
# FIXME deal with the devel probably too much

WORKDIR /tmp/src
RUN curl -fsSL https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.[0-9]*}/openmpi-${OPENMPI_VERSION}.tar.gz | tar --strip-components=1 -xzf -
RUN ./configure CC=$CC FC=$FC CXX=$CXX \
    --prefix=${OPENMPI_HOME} \
    --enable-static \
    --enable-smp-locks \
    --enable-mpi-thread-multiple \
    --with-slurm \
    --with-ucx=${UCX_HOME} \
    --with-ucx-libdir=${UCX_HOME}/lib \
    --with-io-romio-flags=--with-file-system=testfs+ufs+lustre
RUN make -j $(nproc) && make install

FROM shared_components AS cuda_stage

ARG GCC_HOME

COPY --from=gcc_stage ${GCC_HOME} ${GCC_HOME}

ARG CUDA_HOME

# FIXME Why glibc-devel?!?!?
RUN yum install -y which glibc-devel

ENV PATH=${GCC_HOME}/bin:${PATH} \
    LD_LIBRARY_PATH=${GCC_HOME}/lib64

WORKDIR /tmp/src
ADD https://developer.download.nvidia.com/compute/cuda/10.2/Prod/local_installers/cuda_10.2.89_440.33.01_linux.run .
ADD https://developer.download.nvidia.com/compute/cuda/10.2/Prod/patches/1/cuda_10.2.1_linux.run .
ADD https://developer.download.nvidia.com/compute/cuda/10.2/Prod/patches/2/cuda_10.2.2_linux.run .
RUN mkdir -p ${CUDA_HOME}
RUN sh cuda_10.2.89_440.33.01_linux.run --silent --toolkit --no-man-page --installpath=${CUDA_HOME}
RUN sh cuda_10.2.1_linux.run --silent --toolkit --no-man-page --installpath=${CUDA_HOME}
RUN sh cuda_10.2.2_linux.run --silent --toolkit --no-man-page --installpath=${CUDA_HOME}

FROM shared_components AS intel_stage

ARG SLURM_HOME
ARG UCX_HOME
ARG GCC_HOME
ARG OPENMPI_HOME
ARG CUDA_HOME

COPY --from=gcc_stage ${GCC_HOME} ${GCC_HOME}
COPY --from=ucx_stage ${UCX_HOME} ${UCX_HOME}
COPY --from=slurm_stage ${SLURM_HOME} ${SLURM_HOME}
COPY --from=openmpi_stage ${OPENMPI_HOME} ${OPENMPI_HOME}
COPY --from=cuda_stage ${CUDA_HOME} ${CUDA_HOME}

RUN yum install -y \
    numactl-devel
# FIXME maybe only numactl-libs?

RUN rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
RUN yum-config-manager \
    --add-repo https://yum.repos.intel.com/mkl/setup/intel-mkl.repo
RUN yum install -y \
    intel-mkl-2019.5-075.x86_64 && \
    yum clean all

ARG PECAN_INTEL_HOME=/apps/intel/2019/u5
ARG INTEL_DIR_NAME=compilers_and_libraries_2019.5.281
RUN mkdir -p /apps/intel/2019/u5 && \
    ln -s /opt/intel/${INTEL_DIR_NAME} ${PECAN_INTEL_HOME}/${INTEL_DIR_NAME}

# Exposing quite everything, making future modularization more complicated.
# Most likely there will be no future modularization!
ENV CC=${GCC_HOME}/bin/gcc \
    CXX=${GCC_HOME}/bin/g++ \
    FC=${GCC_HOME}/bin/gfortran \
    MPICC=${OPENMPI_HOME}/bin/mpicc \
    MPICXX=${OPENMPI_HOME}/bin/mpicxx \
    MPIFC=${OPENMPI_HOME}/bin/mpifort \
    LD_LIBRARY_PATH=${GCC_HOME}/lib64:${PECAN_INTEL_HOME}/${INTEL_DIR_NAME}/linux/mkl/lib/intel64:${PECAN_INTEL_HOME}/${INTEL_DIR_NAME}/compiler/lib/intel64:${OPENMPI_HOME}/lib
