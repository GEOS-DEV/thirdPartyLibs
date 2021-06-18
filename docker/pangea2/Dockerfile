# The docker base image can be pecan or pangea.
ARG DOCKER_ROOT_IMAGE
FROM ${DOCKER_ROOT_IMAGE} as tpl_toolchain_intersect_geosx_toolchain

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

RUN yum install -y \
    make \
    python \
    zlib-devel

# centos:7.6 offers a 2.8 version of cmake which is too old.
ARG CMAKE_VERSION=3.14.5
RUN curl -s https://cmake.org/files/v${CMAKE_VERSION%.[0-9]*}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz | tar --directory=/usr/local --strip-components=1 -xzf -

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

RUN yum install -y \
    bc \
    file \
    bison \
    flex \
    patch

ARG TMP_DIR=/tmp
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
    openssh-clients \
    texlive \
    graphviz \
    libxml2 \
    git
