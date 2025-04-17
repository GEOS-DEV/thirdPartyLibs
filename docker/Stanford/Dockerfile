# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# The docker base image 
ARG DOCKER_ROOT_IMAGE
FROM $DOCKER_ROOT_IMAGE as tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

RUN yum install -y \
    ca-certificates \
    curl \
    python3 \
    python3-devel \
    zlib-devel \
# Additional spack dependencies
    python3-pip \
    pkgconfig \
    # xz \
    unzip \
    bzip2 \
    && pip3 install virtualenv

# Set locale to bypass ascii codec decode error
ENV LANG='en_US.utf8' \
    LANGUAGE='en_US.utf8' \
    LC_ALL='en_US.utf8'

# Install clingo for Spack
RUN mkdir -p /oak/stanford/groups/tchelepi/geos-sherlock/pythonVenv
RUN cd /oak/stanford/groups/tchelepi/geos-sherlock/pythonVenv && \
    python3 -m venv geosxEnv && \
    source geosxEnv/bin/activate && \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install clingo

# CMake is built by the base image instead of using install-cmake.sh
ENV PATH=/share/software/user/open/cmake/3.31.4/bin:${PATH}

FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

RUN yum install -y \
    make \
    bc \
    file \
    bison \
    flex \
    patch \
    ca-certificates \
    autoconf-2.69 \
    automake \
    git

ARG SPEC

# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOSX_TPL_DIR} && \
     source /oak/stanford/groups/tchelepi/geos-sherlock/pythonVenv/geosxEnv/bin/activate && \
     ./scripts/uberenv/uberenv.py \
       # spack spec defined per image
       --spec "${SPEC}" \
       --spack-env-file=${SRC_DIR}/docker/stanford-spack.yaml \
       --project-json=.uberenv_config.json \
       --prefix ${GEOSX_TPL_DIR} \
       -k && \
# Remove host-config generated for LvArray
     rm lvarray* && \
# Rename and copy spack-generated host-config to root directory
     cp *.cmake /spack-generated.cmake && \
# Remove extraneous spack files
     cd ${GEOSX_TPL_DIR} && \
     rm -rf bin/ build_stage/ misc_cache/ spack/ spack_env/ .spack-db/

FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Extract the generated host-config
COPY --from=tpl_toolchain /spack-generated.cmake /

RUN yum install -y \
    openssh-clients \
    ca-certificates \
    curl \
    python3 \
    texlive \
    graphviz \
    libxml2 \
    git

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-ninja.sh

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
