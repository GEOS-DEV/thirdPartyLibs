# The docker base image has to be pangea3-almalinux8-*
ARG DOCKER_ROOT_IMAGE
FROM ${DOCKER_ROOT_IMAGE} as tpl_toolchain_intersect_geosx_toolchain

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=${INSTALL_DIR}

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

ARG TMP_DIR=/tmp
ARG TPL_SRC_DIR=${TMP_DIR}/thirdPartyLibs
ARG TPL_BUILD_DIR=${TMP_DIR}/build

ARG HOST_CONFIG

COPY . ${TPL_SRC_DIR}
RUN ${TPL_SRC_DIR}/docker/configure_tpl_build.sh
WORKDIR ${TPL_BUILD_DIR}
RUN make

FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain_intersect_geosx_toolchain ${GEOSX_TPL_DIR} ${GEOSX_TPL_DIR}

ENV SCCACHE=/opt/sccache/bin/sccache
