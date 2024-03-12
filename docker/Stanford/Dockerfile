# The docker base image can be pecan or pangea.
ARG DOCKER_ROOT_IMAGE
FROM ${DOCKER_ROOT_IMAGE} as tpl_toolchain_intersect_geosx_toolchain

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

RUN yum install -y \
    python3 \
    zlib-devel

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

RUN yum install -y \
    make \
    bc \
    file \
    bison \
    flex \
    ca-certificates \
    curl \
    patch

ARG TMP_DIR=/tmp
ARG TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ARG TPL_BUILD_DIR=${TMP_DIR}/build

ARG HOST_CONFIG

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/install_cmake.sh
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

RUN curl -fsSL https://github.com/ninja-build/ninja/releases/download/v1.11.1/ninja-linux.zip | zcat > /usr/local/bin/ninja && chmod +x /usr/local/bin/ninja

RUN ${TPL_SRC_DIR}/docker/install_sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
