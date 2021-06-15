# There are far fewer comments on this Dockerfile than on ubuntu's Dockerfile.
# The pattern is equivalent so refer to ubuntu for description.
# Only details that are specific to centos shall be underlined here.
ARG TMP_DIR=/tmp
FROM centos:7.7.1908 AS tpl_toolchain_intersect_geosx_toolchain

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

# The packaged cmake version is too old, we install a newer precompiled version.
ARG CMAKE_VERSION=3.13.3
RUN curl -fsSL https://cmake.org/files/v${CMAKE_VERSION%.[0-9]*}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz | tar --directory=/usr/local --strip-components=1 -xzf -

ARG TMP_DIR
# The trailing / (in ${TMP_DIR}) is here for multiple COPY sources
COPY docker/clang-centos/compiler-wrappers-1-12.tce.ch6.x86_64.rpm \
    docker/clang-centos/gcc493-2.0-6.ch6.x86_64.rpm \
    docker/clang-centos/clang-9.0.0-3-2.tce.ch6.x86_64.rpm \
    ${TMP_DIR}/

# Removing gpg signature warning.
RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

RUN yum -y install \
    make \
    tbb \
    blas-devel \
    lapack-devel \
    zlib-devel \
    ${TMP_DIR}/compiler-wrappers-1-12.tce.ch6.x86_64.rpm \
    ${TMP_DIR}/gcc493-2.0-6.ch6.x86_64.rpm \
    ${TMP_DIR}/clang-9.0.0-3-2.tce.ch6.x86_64.rpm \
    openmpi-devel \
    python

RUN rm ${TMP_DIR}/*.rpm

# The LLNL clang requires CUDA but we do not use it.
# Just creating this empty folder is enough to fake a CUDA install in our configuration process.
RUN mkdir -p /opt/cudatoolkit/10.1

# The centos7 doc suggests to `module load mpi/openmpi-x86_64` but that does not fit quite well with the step by step docker building.
# Defining the environment variables
ENV CC=/usr/tce/packages/clang/clang-9.0.0/bin/clang \
    CXX=/usr/tce/packages/clang/clang-9.0.0/bin/clang++ \
    MPICC=/usr/lib64/openmpi/bin/mpicc \
    MPICXX=/usr/lib64/openmpi/bin/mpicxx \
    MPIEXEC=/usr/lib64/openmpi/bin/mpirun
ENV OMPI_CC=${CC} \
    OMPI_CXX=${CXX}

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

ENV FC=/usr/tce/packages/gcc/gcc-4.9.3/bin/gfortran \
    MPIFC=/usr/lib64/openmpi/bin/mpifort
ENV OMPI_FC=${FC}

RUN yum -y install \
    tbb-devel \
    bc \
    file \
    bison \
    flex \
    patch

ARG TMP_DIR
ARG TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ARG TPL_BUILD_DIR=${TMP_DIR}/build

ARG HOST_CONFIG

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh
WORKDIR ${TPL_BUILD_DIR}
RUN make

FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

RUN yum -y install \
    texlive \
    graphviz* \
    libxml2 \
    git
