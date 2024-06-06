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
# Workaround locally???
#RUN yum install --disablerepo=intel-mkl-repo -y \
    ca-certificates \
    curl \
    python3 \
    zlib-devel \
# Additional spack dependencies
    python3-pip \
    pkgconfig \
    # xz \
    unzip \
    bzip2 \
    && pip3 install virtualenv

# Install clingo for Spack
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install clingo

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh
# Temporary workaround for building newer cmake on local computer connected to lab network
#COPY cmake-3.23.1-linux-x86_64.tar.gz /
#RUN tar --directory=/usr/local  --strip-components=1 -xzf  cmake-3.23.1-linux-x86_64.tar.gz


FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

RUN yum install -y \
# Workaround locally???
#RUN yum install --disablerepo=intel-mkl-repo -y \
    make \
    bc \
    file \
    bison \
    flex \
    patch \
# `ca-certificates`  needed by `git` to download GEOS repo.
    ca-certificates \
    autoconf \
    automake \
    git

# Clone branch with spack configs
# TODO decide landing place of spack recipes
RUN git clone --branch feature/han12/wip_docker_spack_recipes \
              --depth 1 \
          --single-branch \
          https://github.com/GEOS-DEV/GEOS.git

ARG SPEC

# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
# Remove generated host-config for lvarray
RUN --mount=src=.,dst=$SRC_DIR cd GEOS && \
     mkdir -p ${GEOSX_TPL_DIR} && \
     git submodule init scripts/uberenv && \
     git submodule update && \
     ./scripts/uberenv/uberenv.py \
       # Sherlock CPU
       #--spec "%gcc@10.1.0~pygeosx" \
       # Sherloc GPU
       #--spec "%gcc@10.1.0~pygeosx ~pygeosx cuda_arch=70 ^cuda@11.7.1+allow-unsupported-compilers" \
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
     rm -rf bin/ build_stage/ misc_cache/ spack/ spack-env/ .spack-db/

FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Extract the generated host-config
COPY --from=tpl_toolchain /spack-generated.cmake /

RUN yum install -y \
# Workaround locally???
#RUN yum install --disablerepo=intel-mkl-repo -y \
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
