# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# The docker base image has to be pangea3-almalinux8-*
ARG DOCKER_ROOT_IMAGE

FROM $DOCKER_ROOT_IMAGE as tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR
ARG BLD_DIR

# All the environment variables defined in this Dockerfile
# (GEOSX_TPL_DIR but also compiler information like CC, CXX...)
# are part of the image contract (otherwise ARG is used).
# GEOSX use them so consider modifying their names with care.
#
# The installation directory is provided as a docker build argument.
# We forward it using an environment variable.
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Get host config file from docker build arguments
ARG HOST_CONFIG

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
# We now configure the build...
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/configure-tpl.sh
# ... before we compile the TPLs!
WORKDIR $BLD_DIR
RUN --mount=src=.,dst=$SRC_DIR make

# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

ENV SCCACHE=/opt/sccache/bin/sccache
