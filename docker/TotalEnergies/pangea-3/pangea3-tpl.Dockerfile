# syntax=docker/dockerfile:1

#######################################
# Pangea 3 tpl image
#
# Description :
#   - generic image for building geos tpls on Pangea 3 environments
#   - the docker base image can be any pangea3 docker file
#
# Usage :
#   build the image (from the root of the repository!):
#   - podman build --format docker --progress=plain \
#     --build-arg HOST_CONFIG=host-configs/TotalEnergies/pangea-3/pangea3-gcc11.4.0-openmpi-4.1.6.cmake \
#     --build-arg DOCKER_ROOT_IMAGE=onetechssc/pangea3:almalinux8-gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0 \
#     --build-arg INSTALL_DIR=/workrd/SCR/NUM/GEOS_environment/p3/install/tpl/install \
#     -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem \
#     -t onetechssc/geos:tpl_gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0 \
#     -f docker/TotalEnergies/pangea-3/pangea3-tpl.Dockerfile .
#   run the image:
#   - podman run -it --detach --privileged --name pangea3_tpl -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem localhost/onetechssc/geos:tpl_gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0
#   - podman exec -it pangea3_tpl /bin/bash
#   push the image (requires to be part of the onetechssc docker organization):
#   - podman login docker.io
#   - podman push localhost/onetechssc/geos:tpl_gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0 docker://docker.io/onetechssc/geos:tpl_gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0
#   build geos from the image (from the root of geos reopsitory!):
#  - podman run --name pangea4_geos \
#    -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem \
#    -v .:/tmp/geos \
#    localhost/onetechssc/geos:tpl_gcc11.4.0-openmpi4.1.6-cuda11.8.0-openblas0.3.18_v2.0 \
#    /tmp/geos/scripts/ci_build_and_test_in_container.sh \
#    --host-config host-configs/TotalEnergies/pangea-3/pangea3-gcc11.4.0-openmpi-4.1.6.cmake \
#    --repository /tmp/geos --cmake-build-type Release --install-dir /tmp/install --build-exe-only
#######################################

# -------------------------------------
# PANGEA3 - TPL BASE
ARG DOCKER_ROOT_IMAGE
FROM $DOCKER_ROOT_IMAGE as tpl_toolchain_intersect_geosx_toolchain
# ------
# LABELS
LABEL description="Pangea 3 image : geos_tpl"
LABEL version="2.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
# The installation directory is provided as a docker build argument
ARG INSTALL_DIR
# ------
# ENV
# All the environment variables defined in this Dockerfile
# (GEOSX_TPL_DIR but also compiler information like CC, CXX...)
# are part of the image contract (otherwise ARG is used).
# GEOSX use them so consider modifying their names with care.
ENV GEOS_TPL_DIR=$INSTALL_DIR
ENV GEOSX_TPL_DIR=$GEOS_TPL_DIR

# -------------------------------------
# PANGEA3 - TPL TOOLCHAIN
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
# ------
# ARGS
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build
# Get host config file from docker build arguments
ARG HOST_CONFIG
# ------
# INSTALL
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/configure-tpl.sh
#   - build TPLs
WORKDIR $BLD_DIR
RUN --mount=src=.,dst=$SRC_DIR make

# -------------------------------------
# PANGEA3 - GEOS TOOLCHAIN
# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

ENV SCCACHE=/opt/sccache/bin/sccache
