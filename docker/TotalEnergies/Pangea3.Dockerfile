# The docker base image has to be pangea3-almalinux8-*
ARG DOCKER_ROOT_IMAGE
FROM ${DOCKER_ROOT_IMAGE} as tpl_toolchain_intersect_geosx_toolchain

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

RUN dnf install -y \
    python38-devel \
    zlib-devel


RUN dnf install -y \
    make \
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

#RUN dnf -y install \
#    openssh-clients \
#    texlive \
#    graphviz \
#    libxml2 \
#    git

#RUN curl -fsSL https://github.com/ninja-build/ninja/releases/download/v1.11.1/ninja-linux.zip | zcat > /usr/local/bin/ninja && chmod +x /usr/local/bin/ninja

#RUN mkdir -p /opt/sccache/bin && \
#    curl -fsSL https://github.com/mozilla/sccache/releases/download/v0.7.3/sccache-v0.7.3-x86_64-unknown-linux-musl.tar.gz | tar --directory=/opt/sccache/bin --strip-components=1 -xzf -
#ENV SCCACHE=/opt/sccache/bin/sccache
