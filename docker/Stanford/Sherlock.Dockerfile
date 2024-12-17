# This Dockerfile aims at reproducing (some part of) the SHERLOCK environment.
#
# While loading module ompi4.1.2 on Sherlock, the following are aut-loaded:
#         UCX/1.12.1
# 		  LIBFABRIC/1.14.0
# Moreover ompi is compiled with slurm pmi(x) and libevent support
# this is not reproduced here.

ARG GCC_VERSION=10.1.0
ARG OPENMPI_VERSION=4.1.2
ARG OPENBLAS_VERSION=0.3.10
ARG ZLIB_VERSION=1.2.11
ARG CUDA_VERSION=11.7.1
ARG CUDA_SUBVERSION=515.65.01

# Main software root installation directory in SHERLOCK
ARG SHERLOCK_ROOT_INSTALL_DIR=/share/software/user/open
# `gcc` and `openmpi` installation directories
ARG SHERLOCK_GCC_INSTALL_DIR=${SHERLOCK_ROOT_INSTALL_DIR}/gcc/${GCC_VERSION}
ARG SHERLOCK_OPENMPI_INSTALL_DIR=${SHERLOCK_ROOT_INSTALL_DIR}/openmpi/${OPENMPI_VERSION}
ARG SHERLOCK_OPENBLAS_INSTALL_DIR=${SHERLOCK_ROOT_INSTALL_DIR}/openblas/${OPENBLAS_VERSION}
ARG SHERLOCK_ZLIB_INSTALL_DIR=${SHERLOCK_ROOT_INSTALL_DIR}/zlib/${ZLIB_VERSION}
ARG SHERLOCK_CUDA_INSTALL_DIR=${SHERLOCK_ROOT_INSTALL_DIR}/cuda/${CUDA_VERSION}

FROM centos:7.9.2009 AS shared_components

RUN yum install -y \
        glibc-devel

# We'll compile and deploy a version of `gcc` in this stage.
FROM shared_components AS gcc_stage

ARG GCC_VERSION
ARG SHERLOCK_GCC_INSTALL_DIR

RUN yum install -y \
    make \
# Yes, we need a compiler to compile the compiler :)
    gcc \
    gcc-c++ \
    wget \
    bzip2

WORKDIR /tmp/src
RUN curl -s https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz | tar --strip-components=1 -xzf -

# This embedded script downloads 4 `gcc` dependencies: `isl`, `gmp`, `mpfr` and `mpc`.
RUN ./contrib/download_prerequisites

# Fortran compiler is build and available for both TPL and GEOSX,
# even though GEOSX should not need it.
RUN ./configure --prefix=${SHERLOCK_GCC_INSTALL_DIR} --disable-multilib --enable-languages=c,c++,fortran && \
    make -j $(nproc) && \
    make install-strip

FROM gcc_stage AS cuda_openmpi_stage

ARG SHERLOCK_GCC_INSTALL_DIR
ARG SHERLOCK_CUDA_INSTALL_DIR
ARG CUDA_VERSION
ARG CUDA_SUBVERSION

# FIXME Why glibc-devel?!?!?
RUN yum install -y which glibc-devel

ENV PATH=${SHERLOCK_GCC_INSTALL_DIR}/bin:${PATH} \
    LD_LIBRARY_PATH=${SHERLOCK_GCC_INSTALL_DIR}/lib64

WORKDIR /tmp/src
ADD https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/cuda_${CUDA_VERSION}_${CUDA_SUBVERSION}_linux.run .
RUN mkdir -p ${SHERLOCK_CUDA_INSTALL_DIR}
RUN sh cuda_${CUDA_VERSION}_${CUDA_SUBVERSION}_linux.run --silent --toolkit --no-man-page --installpath=${SHERLOCK_CUDA_INSTALL_DIR}

RUN rm -rf /tmp/src

# `openmpi` will be build and deployed during this stage.
ARG OPENMPI_VERSION
ARG SHERLOCK_GCC_INSTALL_DIR
ARG SHERLOCK_OPENMPI_INSTALL_DIR

ENV CC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gcc \
    CXX=${SHERLOCK_GCC_INSTALL_DIR}/bin/g++ \
    FC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gfortran \
    LD_LIBRARY_PATH=${SHERLOCK_GCC_INSTALL_DIR}/lib64

WORKDIR /tmp/src
RUN curl -s https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.[0-9]*}/openmpi-${OPENMPI_VERSION}.tar.gz | tar --strip-components=1 -xzf -

RUN yum install -y \
    make \
    perl

# compiled with additional option on Sherlock
# --with-slurm
# --with-pmix --with-pmi
# --with-libevent=/usr
# left out for the sake of simplicity --
RUN ./configure --prefix=${SHERLOCK_OPENMPI_INSTALL_DIR} \
	--with-cuda=${SHERLOCK_CUDA_INSTALL_DIR} \
	--without-verbs \
	&& make -j $(nproc) \
	&& make install

FROM gcc_stage AS blas_stage

#openblas and lapack versions
ARG OPENBLAS_VERSION

#retrieve env
ARG SHERLOCK_ROOT_INSTALL_DIR
ARG SHERLOCK_GCC_INSTALL_DIR
ARG SHERLOCK_OPENMPI_INSTALL_DIR
ARG SHERLOCK_OPENBLAS_INSTALL_DIR

COPY --from=gcc_stage ${SHERLOCK_GCC_INSTALL_DIR} ${SHERLOCK_GCC_INSTALL_DIR}

RUN yum install -y \
    make \
    perl

ENV CC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gcc \
    CXX=${SHERLOCK_GCC_INSTALL_DIR}/bin/g++ \
    FC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gfortran \
    LD_LIBRARY_PATH=${SHERLOCK_GCC_INSTALL_DIR}/lib64

WORKDIR /tmp/src
RUN curl -sL https://github.com/xianyi/OpenBLAS/archive/refs/tags/v${OPENBLAS_VERSION}.tar.gz | tar --strip-components=1 -xzf -


# Beware openblas might fail to auto-detect arch on which the docker is running
# if the chip is too new for version 0.3. This would make this docker file obsolete
# and force to find another combination of gcc-ompi-cuda-blas that are accessible on Sherlock
RUN make && make install PREFIX=${SHERLOCK_OPENBLAS_INSTALL_DIR}


#new stage for zlib
FROM gcc_stage AS zlib_stage

ARG ZLIB_VERSION

ARG SHERLOCK_ROOT_INSTALL_DIR
ARG SHERLOCK_GCC_INSTALL_DIR
ARG SHERLOCK_ZLIB_INSTALL_DIR

RUN yum install -y \
    make \
    perl

ENV CC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gcc \
    CXX=${SHERLOCK_GCC_INSTALL_DIR}/bin/g++ \
    FC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gfortran \
    LD_LIBRARY_PATH=${SHERLOCK_GCC_INSTALL_DIR}/lib64

WORKDIR /tmp/src
RUN curl -sL https://github.com/madler/zlib/archive/refs/tags/v${ZLIB_VERSION}.tar.gz | tar --strip-components=1 -xzf -

RUN ./configure --prefix=${SHERLOCK_ZLIB_INSTALL_DIR}  && \
    make -j $(nproc) && \
    make install

FROM shared_components AS final_stage

ARG SHERLOCK_GCC_INSTALL_DIR
ARG SHERLOCK_OPENMPI_INSTALL_DIR
ARG SHERLOCK_OPENBLAS_INSTALL_DIR
ARG SHERLOCK_ZLIB_INSTALL_DIR
ARG SHERLOCK_CUDA_INSTALL_DIR

COPY --from=gcc_stage ${SHERLOCK_GCC_INSTALL_DIR} ${SHERLOCK_GCC_INSTALL_DIR}
COPY --from=cuda_openmpi_stage ${SHERLOCK_OPENMPI_INSTALL_DIR} ${SHERLOCK_OPENMPI_INSTALL_DIR}
COPY --from=blas_stage ${SHERLOCK_OPENBLAS_INSTALL_DIR} ${SHERLOCK_OPENBLAS_INSTALL_DIR}
COPY --from=zlib_stage ${SHERLOCK_ZLIB_INSTALL_DIR} ${SHERLOCK_ZLIB_INSTALL_DIR}
COPY --from=cuda_openmpi_stage ${SHERLOCK_CUDA_INSTALL_DIR} ${SHERLOCK_CUDA_INSTALL_DIR}

# GEOSX does not need fortran compilers; we expose it anyway (see comments above).
ENV CC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gcc \
    CXX=${SHERLOCK_GCC_INSTALL_DIR}/bin/g++ \
    FC=${SHERLOCK_GCC_INSTALL_DIR}/bin/gfortran \
    MPICC=${SHERLOCK_OPENMPI_INSTALL_DIR}/bin/mpicc \
    MPICXX=${SHERLOCK_OPENMPI_INSTALL_DIR}/bin/mpic++ \
    MPIFC=${SHERLOCK_OPENMPI_INSTALL_DIR}/bin/mpifort \
    MPIEXEC=${SHERLOCK_OPENMPI_INSTALL_DIR}/bin/mpiexec \
# An additional `LD_LIBRARY_PATH` action is needed for the tools to work.
    LD_LIBRARY_PATH=${SHERLOCK_OPENMPI_INSTALL_DIR}/lib:${SHERLOCK_GCC_INSTALL_DIR}/lib64:${SHERLOCK_OPENBLAS_INSTALL_DIR}/lib:${SHERLOCK_CUDA_INSTALL_DIR}/lib64:${SHERLOCK_ZLIB_INSTALL_DIR}/lib:${LD_LIBRARY_PATH}


