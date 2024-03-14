# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# The docker base image can be pecan or pangea.
ARG DOCKER_ROOT_IMAGE
FROM $DOCKER_ROOT_IMAGE as tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

RUN yum install -y \
    ca-certificates \
    curl \
    python3 \
    zlib-devel

RUN --mount=src=.,dst=$TPL_SRC_DIR $TPL_SRC_DIR/docker/install_cmake.sh

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

RUN yum install -y \
    make \
    bc \
    file \
    bison \
    flex \
    patch

ARG HOST_CONFIG

RUN --mount=src=.,dst=$TPL_SRC_DIR $TPL_SRC_DIR/docker/configure_tpl_build.sh
WORKDIR $BLD_DIR
RUN --mount=src=.,dst=$TPL_SRC_DIR make

FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

RUN yum -y install \
    openssh-clients \
    ca-certificates \
    curl \
    python3 \
    texlive \
    graphviz \
    libxml2 \
    git

RUN --mount=src=.,dst=$TPL_SRC_DIR $TPL_SRC_DIR/docker/install_ninja.sh

RUN --mount=src=.,dst=$TPL_SRC_DIR $TPL_SRC_DIR/docker/install_sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
