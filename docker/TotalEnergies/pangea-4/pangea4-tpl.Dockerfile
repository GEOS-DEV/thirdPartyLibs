#######################################
# Pangea 4 tpl image
#
# Description :
#   - generic image for building geos tpls on Pangea 4 environments
#   - the docker base image must match the spack environment
#   - tools of the base image are expected to be sourced in the set_env.sh script
#
# Usage :
#   build the image (from the root of the repository!):
#   - podman build --format docker --progress=plain \
#     --build-arg DOCKER_ROOT_IMAGE=onetechssc/pangea4:gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0 \
#     --build-arg INSTALL_DIR=/workrd/SCR/NUM/GEOS_environment/p4/install/tpl/install \
#     -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem \
#     -t onetechssc/geos:tpl_gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0 \
#     -f docker/TotalEnergies/pangea-4/pangea4-tpl.Dockerfile .
#   run the image:
#   - podman run -it --detach --privileged --name pangea4_tpl -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem localhost/onetechssc/geos:tpl_gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0
#   - podman exec -it pangea4_tpl /bin/bash
#   push the image (requires to be part of the onetechssc docker organization):
#   - podman login docker.io
#   - podman push localhost/onetechssc/geos:tpl_gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0 docker://docker.io/onetechssc/geos:tpl_gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0
#   build geos from the image (from the root of geos reopsitory!):
#  - podman run --name pangea4_geos \
#    -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem \
#    -v .:/tmp/geos \
#    localhost/onetechssc/geos:tpl_gcc12.1-hpcxompi2.20.0-onemkl2023.2.0_v1.0 \
#    /tmp/geos/scripts/ci_build_and_test_in_container.sh \
#    --host-config /spack-generated.cmake \
#    --repository /tmp/geos --cmake-build-type Release --install-dir /tmp/install --build-exe-only
#######################################

# -------------------------------------
# PANGEA4 - TPL BASE
ARG DOCKER_ROOT_IMAGE
FROM $DOCKER_ROOT_IMAGE AS pangea4_tpl_base
# ------
# LABELS
LABEL description="Pangea 4 image : geos_tpl"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG INSTALL_DIR
# ------
# ENV
ENV GEOS_TPL_DIR=$INSTALL_DIR
ENV GEOSX_TPL_DIR=$GEOS_TPL_DIR

# -------------------------------------
# PANGEA4 - TPL BUILDER
FROM pangea4_tpl_base AS pangea4_tpl_builder
# ------
# ARGS
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/src
# ------
# INSTALL
# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOS_TPL_DIR} && \
# - run uberenv
     ./scripts/uberenv/uberenv.py \
       --spec "%gcc@12.2.1 ~openmp~pygeosx" \
       --spack-env-file=${SRC_DIR}/docker/TotalEnergies/pangea-4/pangea4-spack.yaml \
       --project-json=.uberenv_config.json \
       --prefix ${GEOS_TPL_DIR} \
       -k && \
# - remove host-config generated for LvArray
     rm lvarray* && \
# - rename and copy spack-generated host-config to root directory
     cp *.cmake /spack-generated.cmake && \
# - remove extraneous spack files
     cd ${GEOS_TPL_DIR} && \
     rm -rf bin/ build_stage/ misc_cache/ spack/ spack_env/ .spack-db/

# -------------------------------------
# PANGEA4 - TPL TOOLCHAIN
FROM pangea4_tpl_base AS pangea4_tpl_toolchain
# ------
# ARGS
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/src
# ------
# INSTALL
#   - copy TPLs install directory
COPY --from=pangea4_tpl_builder $GEOS_TPL_DIR $GEOS_TPL_DIR
#   - copy the generated host-config
COPY --from=pangea4_tpl_builder /spack-generated.cmake /
#   - install ninja for geos build
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-ninja.sh
#   - install `sccache` binaries to speed up the build of `geos`
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
# ------
# ENV
ENV SCCACHE=/opt/sccache/bin/sccache
# ------
# ENTRYPOINT
# set entry point for geos ci build script
ENTRYPOINT ["/bin/bash", "-c", "source /root/.setup_env.sh && exec \"$@\"", "--"]