#######################################
# Pangea 4 image : gcc - hpcxompi - onemkl
#
# Description :
#   - generic image for building geos tpls on Pangea 4 environments
#   - the docker base image can be any pangea4 docker file
#   - tools of the base image are expected to be available in prgenv spack environment
#######################################

# -------------------------------------
# PANGEA4 - TPL TOOLCHAIN
ARG DOCKER_ROOT_IMAGE
FROM $DOCKER_ROOT_IMAGE as pangea4_tpl_toolchain
# ------
# LABELS
LABEL description="Pangea 4 image : geos_tpl"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build
ARG INSTALL_DIR
ARG HOST_CONFIG
# ------
# ENV
ENV GEOSX_TPL_DIR=$INSTALL_DIR
# ------
# INSTALL
RUN spack env activate prgenv && \
    --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/configure-tpl.sh
WORKDIR $BLD_DIR
RUN spack env activate prgenv && \
    --mount=src=.,dst=$SRC_DIR make
COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR
# ------
# CACHE
# install `sccache` binaries to speed up the build of `geos`
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
