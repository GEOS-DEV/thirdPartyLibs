# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp 
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

FROM nvidia/cuda:11.8.0-devel-centos7 AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

RUN sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/*.repo && \
    sed -i s/^#.*baseurl=http/baseurl=https/g /etc/yum.repos.d/*.repo && \
    sed -i s/^mirrorlist=http/#mirrorlist=https/g /etc/yum.repos.d/*.repo 

# Using gcc 8.3.1 provided by the Software Collections (SCL).
RUN yum install -y \
    centos-release-scl
    
# Modify the SCLo repository configuration
RUN sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-SCLo-scl.repo && \
    sed -i 's|^baseurl=http://mirror.centos.org/centos/\$releasever/sclo/\$basearch/rh|baseurl=http://vault.centos.org/7.9.2009/sclo/x86_64/rh|g' /etc/yum.repos.d/CentOS-SCLo-scl.repo && \
    sed -i 's|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo && \
    sed -i 's|^baseurl=http://mirror.centos.org/centos/\$releasever/sclo/\$basearch/rh|baseurl=http://vault.centos.org/7.9.2009/sclo/x86_64/rh|g' /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo

# Install necessary tools and update the system
RUN yum -y update && \
    yum -y install yum-utils    

RUN yum install -y \
    devtoolset-8-gcc \
    devtoolset-8-gcc-c++ \
    devtoolset-8-gcc-gfortran

# Installing dependencies
RUN yum -y install \
    ca-certificates \
    curl \
    tbb \
    blas-devel \
    lapack-devel \
    zlib-devel \
    openmpi-devel \
    python3 \
# Additional spack dependencies
    python3-pip \
    # pkgconfig \
    # xz \
    unzip \
    bzip2 \
    gnupg \
    && pip3 install virtualenv

# Install clingo for Spack
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install clingo

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

# Installing TPL's
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

RUN yum install -y \
    tbb-devel \
    make \
    bc \
    file \
    bison \
    flex \
    patch \
    ca-certificates \
    autoconf \
    automake \
    git

# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOSX_TPL_DIR} && \
# Create symlink to openmpi include directory
     ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include && \
     ./scripts/uberenv/uberenv.py \
       --spec "%gcc@8+cuda~uncrustify~openmp~pygeosx cuda_arch=70 ^cuda@11.8.0+allow-unsupported-compilers ^caliper~gotcha~sampler~libunwind~libdw~papi" \
       --spack-env-file=${SRC_DIR}/docker/spack.yaml \
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

# Extract only TPL's from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Extract the generated host-config
COPY --from=tpl_toolchain /spack-generated.cmake /

RUN yum install -y \
    openssh-client \
    ca-certificates \
    curl \
    python3 \
    texlive \
    graphviz \
    git && \
# Regenerate symlink to openmpi include directory
    ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-ninja.sh

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
