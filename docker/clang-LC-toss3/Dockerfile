# There are far fewer comments on this Dockerfile than on ubuntu's Dockerfile.
# The pattern is equivalent so refer to ubuntu for description.
# Only details that are specific to centos shall be underlined here.
ARG TMP_DIR=/tmp
FROM centos:7.5.1804 AS tpl_toolchain_intersect_geosx_toolchain

ENV GEOSX_TPL_DIR=/opt/GEOSX_TPL
# The same Dockerfile is used to install both 6.0.1 and 7.0.0 clang versions.
ARG CLANG_VERSION

ARG TMP_DIR
# The packaged cmake version is too old, we install a newer precompiled version.
ADD https://cmake.org/files/v3.13/cmake-3.13.3-Linux-x86_64.tar.gz ${TMP_DIR}/
RUN tar --directory=/usr/local --strip-components=1 -xzf ${TMP_DIR}/cmake-3.13.3-Linux-x86_64.tar.gz && \
    rm ${TMP_DIR}/cmake-3.13.3-Linux-x86_64.tar.gz

# The trailing / (in ${TMP_DIR}) is here for multiple COPY sources
COPY docker/clang-LC-toss3/compiler-wrappers-1-8.tce.ch6_1.x86_64.rpm \
    docker/clang-LC-toss3/gcc493-2.0-6.ch6.x86_64.rpm \
    docker/clang-LC-toss3/clang-${CLANG_VERSION}-1-1.tce.ch6_2.x86_64.rpm \
    ${TMP_DIR}/

# Removing gpg signature warning.
RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

RUN yum -y install \
    make \
    tbb \
    blas-devel \
    lapack-devel \
    zlib-devel \
    ${TMP_DIR}/compiler-wrappers-1-8.tce.ch6_1.x86_64.rpm \
    ${TMP_DIR}/gcc493-2.0-6.ch6.x86_64.rpm \
    ${TMP_DIR}/clang-${CLANG_VERSION}-1-1.tce.ch6_2.x86_64.rpm \
    openmpi-devel \
    python

RUN rm ${TMP_DIR}/*.rpm

# FIXME Is it possible to suppress fortran and reinstall it after?
#       Is it worth the price?

# FIXME Is it possible to use modules like centos7.5 suggests: 
#       `module load mpi/openmpi-x86_64` ?
ENV CC=/usr/tce/packages/clang/clang-${CLANG_VERSION}/bin/clang \
    CXX=/usr/tce/packages/clang/clang-${CLANG_VERSION}/bin/clang++ \
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

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh
WORKDIR ${TPL_BUILD_DIR}
RUN make

FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}
