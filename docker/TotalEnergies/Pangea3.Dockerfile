# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# The docker base image has to be pangea3-almalinux8-*
ARG DOCKER_ROOT_IMAGE

FROM $DOCKER_ROOT_IMAGE as tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR
ARG BLD_DIR

# Install additional required packages for spack
RUN dnf clean all && \
    dnf -y update && \
    dnf -y install \
        autoconf \
        automake \
        libtool \
        bzip2 \
        unzip

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
#ARG HOST_CONFIG

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain

# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOSX_TPL_DIR} && \
# Create symlink to existing libraries sp spack can find
     ln -s /usr/lib64/libhwloc.so.15 /usr/lib64/libhwloc.so && \
     ln -s /usr/lib64/libibverbs.so.1.14.48.0 /usr/lib64/libibverbs.so && \
     ln -s /usr/lib64/libnsl.so.2.0.0  /usr/lib64/libnsl.so && \
     ln -s /usr/lib64/librdmacm.so.1.3.48.0  /usr/lib64/librdmacm.so && \
     ln -s /usr/lib64/liblustreapi.so.1 /usr/lib64/liblustreapi.so && \
# Run uberenv
     ./scripts/uberenv/uberenv.py \
       --spec "%gcc@9.4.0+cuda~uncrustify~openmp~pygeosx cuda_arch=70 ^cuda@11.5.0+allow-unsupported-compilers ^caliper~gotcha~sampler~libunwind~libdw~papi" \
       --spack-env-file=${SRC_DIR}/docker/pangea3-spack.yaml \
       --project-json=.uberenv_config.json \
       --prefix ${GEOSX_TPL_DIR} \
       -k && \
# Remove host-config generated for LvArray
     rm lvarray* && \
# Rename and copy spack-generated host-config to root directory
     cp *.cmake /spack-generated-wave-solver-only.cmake && \
# Remove extraneous spack files
     cd ${GEOSX_TPL_DIR} && \
     rm -rf bin/ build_stage/ misc_cache/ spack/ spack_env/ .spack-db/

# Build only the wave solver for Pangea 3
RUN echo 'set ( GEOS_ENABLE_CONTACT OFF CACHE BOOL "" FORCE )' >> /spack-generated-wave-solver-only.cmake && \
    echo 'set ( GEOS_ENABLE_FLUIDFLOW OFF CACHE BOOL "" FORCE )' >> /spack-generated-wave-solver-only.cmake && \
    echo 'set ( GEOS_ENABLE_INDUCEDSEISMICITY OFF CACHE BOOL "" FORCE )' >> /spack-generated-wave-solver-only.cmake && \
    echo 'set ( GEOS_ENABLE_MULTIPHYSICS OFF CACHE BOOL "" FORCE )' >> /spack-generated-wave-solver-only.cmake && \
    echo 'set ( GEOS_ENABLE_SIMPLEPDE OFF CACHE BOOL "" FORCE )' >> /spack-generated-wave-solver-only.cmake && \
    echo 'set ( GEOS_ENABLE_SOLIDMECHANICS OFF CACHE BOOL "" FORCE )' >> /spack-generated-wave-solver-only.cmake && \
    echo 'set ( GEOS_ENABLE_SURFACEGENERATION OFF CACHE BOOL "" FORCE )' >> /spack-generated-wave-solver-only.cmake


# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Extract the generated host-config
COPY --from=tpl_toolchain /spack-generated-wave-solver-only.cmake /

# Regenerate symlinks for existing libraries
RUN  ln -s /usr/lib64/libhwloc.so.15 /usr/lib64/libhwloc.so && \
     ln -s /usr/lib64/libibverbs.so.1.14.48.0 /usr/lib64/libibverbs.so && \
     ln -s /usr/lib64/libnsl.so.2.0.0  /usr/lib64/libnsl.so && \
     ln -s /usr/lib64/librdmacm.so.1.3.48.0  /usr/lib64/librdmacm.so && \
     ln -s /usr/lib64/liblustreapi.so.1 /usr/lib64/liblustreapi.so

ENV SCCACHE=/opt/sccache/bin/sccache
