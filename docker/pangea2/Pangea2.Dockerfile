# This Dockerfile aims at reproducing (some part of) the Pangea2 environment.
# Will be availble a `gcc` installation, an `openmpi` version compiled with it.
# And intel libraries that provide, amongst other, some BLAS and LAPACK implementations.
# The installation paths are respected, such that any hard coded path should no generate troubles.
#
# The `gcc` and `openmpi` versions are fully parametrised by the following two arguments.
# Consider overriding them from the `--build-arg` command line or directly in the file.
# The intel tools are a little bit more complicated: just one version number is not obvious
# to fully determine the installation. For the moment you shall go to the intel section (last) for customisation.
ARG GCC_VERSION=8.3.0
ARG OPENMPI_VERSION=2.1.5

# Main software root installation directory in Pangea2
ARG PANGEA_ROOT_INSTALL_DIR=/data_local/sw
# `gcc` and `openmpi` installation directories
ARG PANGEA_GCC_INSTALL_DIR=${PANGEA_ROOT_INSTALL_DIR}/gcc/RHEL7/${GCC_VERSION}
ARG PANGEA_OPENMPI_INSTALL_DIR=${PANGEA_ROOT_INSTALL_DIR}/OpenMPI/RHEL7/${OPENMPI_VERSION}/gcc/${GCC_VERSION}

# This stage is technical. Since we use (and abuse) multi-stage builds,
# we must be careful to have all the runtime dependencies available.
FROM centos:7.6.1810 AS shared_components

RUN yum install -y \
        glibc-devel

# We'll compile and deploy a version of `gcc` in this stage.
FROM shared_components AS gcc_stage

ARG GCC_VERSION
ARG PANGEA_GCC_INSTALL_DIR

RUN yum install -y \
    make \
# Yes, we need a compiler to compile the compiler :)
    gcc \
    gcc-c++ \
# wget is installed because the download_prerequisites script has problems with the curl fallback.
    wget \
# bzip2 is installed because some of the `gcc` prerequisites are in bz2 format
    bzip2

# While repeated multiple times, the source folder may be different for each stage.
# It is therefore useless to make it a global argument.
# Note WORKDIR creates the directory.
WORKDIR /tmp/src
RUN curl -s https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.gz | tar --strip-components=1 -xzf -

# This embedded script downloads 4 `gcc` dependencies: `isl`, `gmp`, `mpfr` and `mpc`.
RUN ./contrib/download_prerequisites

# Fortran compiler is build and available for both TPL and GEOSX,
# even though GEOSX should not need it.
# Being extremely precise on this would require quite some work,
# for a protection which is already granted by the ubuntu images.
# This would also prevent other tools from using this docker image.

# No need for 32 bits libraries.
RUN ./configure --prefix=${PANGEA_GCC_INSTALL_DIR} --disable-multilib --enable-languages=c,c++,fortran && \
    make -j $(nproc) && \
    make install-strip

# `openmpi` will be build and deployed during this stage.
# It copies the brand new `gcc` installation, but not the system one.
# This reduces the risk of collision (compilers and runtime).
FROM shared_components AS openmpi_stage

ARG OPENMPI_VERSION
ARG PANGEA_GCC_INSTALL_DIR
ARG PANGEA_OPENMPI_INSTALL_DIR

COPY --from=gcc_stage ${PANGEA_GCC_INSTALL_DIR} ${PANGEA_GCC_INSTALL_DIR}

ENV CC=${PANGEA_GCC_INSTALL_DIR}/bin/gcc \
    CXX=${PANGEA_GCC_INSTALL_DIR}/bin/g++ \
    FC=${PANGEA_GCC_INSTALL_DIR}/bin/gfortran \
    LD_LIBRARY_PATH=${PANGEA_GCC_INSTALL_DIR}/lib64

WORKDIR /tmp/src
RUN curl -s https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.[0-9]*}/openmpi-${OPENMPI_VERSION}.tar.gz | tar --strip-components=1 -xzf -

RUN yum install -y \
    make \
    perl

# We can use `ompi_info` in the Pangea2 environment to retrieve the exact compilation options.
# But depending on the versions of `openmpi`, this information may not be availble.
# Note that our `openmpi` does not bring LSF support.
# This should not be a problem since most use cases would require a link against some MPI library.
# And I do not even know if this LSF support is exposed by `openmpi`...
RUN ./configure --prefix=${PANGEA_OPENMPI_INSTALL_DIR} && make -j $(nproc) && make install
# FIXME One could consider stripping the openmpi binaries.

FROM shared_components

# We'll install the intel components through the intel rpm repositories.
# The installed packages are in `/opt/intel`.
RUN rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2019.PUB
RUN yum-config-manager \
        --add-repo https://yum.repos.intel.com/mkl/setup/intel-mkl.repo \
        --add-repo https://yum.repos.intel.com/ipp/setup/intel-ipp.repo \
        --add-repo https://yum.repos.intel.com/tbb/setup/intel-tbb.repo \
        --add-repo https://yum.repos.intel.com/daal/setup/intel-daal.repo

# Installing the `2019.3` versions of some scientific libraries.
RUN yum install -y \
    intel-mkl-64bit-2019.3-062 \
    intel-ipp-64bit-2019.3-062 \
# tbb is a .4 build (which is consistent with Pangea's installation). The .3 version does not exist!
    intel-tbb-64bit-2019.4-062 \
# FIXME I am not sure that we need intel-daal
    intel-daal-64bit-2019.3-062
# FIXME Note that there are FAR TOO MANY intel packages with this simple command line (e.g. doc, conda, 32bits (surprisingly).
#       Be smarter and select the packages more carefully to save space and time when retrieve the docker image.


ARG PANGEA_ROOT_INSTALL_DIR
ARG PANGEA_GCC_INSTALL_DIR
ARG PANGEA_OPENMPI_INSTALL_DIR

COPY --from=gcc_stage ${PANGEA_GCC_INSTALL_DIR} ${PANGEA_GCC_INSTALL_DIR}
COPY --from=openmpi_stage ${PANGEA_OPENMPI_INSTALL_DIR} ${PANGEA_OPENMPI_INSTALL_DIR}

RUN yum clean all

# The rpm installation do not install like in Pangea2.
# We build a symbolic link to the proper location.
ARG PANGEA_INTEL_HOME=${PANGEA_ROOT_INSTALL_DIR}/intel/RHEL7
ARG INTEL_DIR_NAME=compilers_and_libraries_2019.3.199
RUN mkdir -p ${PANGEA_INTEL_HOME} && \
    ln -s /opt/intel/${INTEL_DIR_NAME} ${PANGEA_INTEL_HOME}/${INTEL_DIR_NAME}
ARG PANGEA_INTEL_DIR=${PANGEA_INTEL_HOME}/${INTEL_DIR_NAME}/linux

# GEOSX does not need fortran compilers; we expose it anyway (see comments above).
ENV CC=${PANGEA_GCC_INSTALL_DIR}/bin/gcc \
    CXX=${PANGEA_GCC_INSTALL_DIR}/bin/g++ \
    FC=${PANGEA_GCC_INSTALL_DIR}/bin/gfortran \
    MPICC=${PANGEA_OPENMPI_INSTALL_DIR}/bin/mpicc \
    MPICXX=${PANGEA_OPENMPI_INSTALL_DIR}/bin/mpic++ \
    MPIFC=${PANGEA_OPENMPI_INSTALL_DIR}/bin/mpifort \
    MPIEXEC=${PANGEA_OPENMPI_INSTALL_DIR}/bin/mpiexec \
# An additional `LD_LIBRARY_PATH` action is needed for the tools to work.
    LD_LIBRARY_PATH=${PANGEA_OPENMPI_INSTALL_DIR}/lib:${PANGEA_GCC_INSTALL_DIR}/lib64:${PANGEA_INTEL_DIR}/compiler/lib/intel64_lin:${PANGEA_INTEL_DIR}/mkl/lib/intel64_lin:${PANGEA_INTEL_DIR}/tbb/lib/intel64_lin/gcc4.1:${PANGEA_INTEL_DIR}/ipp/lib/intel64_lin:${PANGEA_INTEL_DIR}/daal/lib/intel64_lin:${LD_LIBRARY_PATH}
# In the future, if we manage to use this image to test against intel compilers,
# it may be wise not to expose those environment variables and let the client select its tools.
# Another solution would be to build yet another image, but that may end expensive.
