# TPL build Dockerfile for ROCm/HIP images.
#
# Unlike docker/tpl-ubuntu.Dockerfile, this file does NOT layer on one of the
# geosx/ubuntu:* images from https://github.com/GEOS-DEV/docker_base_images.
# AMD's own rocm/dev-ubuntu-* image already ships the amdclang toolchain and the
# ROCm math libraries, so DOCKER_BASE_IMAGE points straight at it and the
# toolchain bits the geosx base images would normally provide (compiler, cmake)
# are installed here instead.
#
# The matrix in .github/workflows/docker_build_tpls.yml selects the base image,
# the spack toolchain (SPEC) and the AMD GPU target.

# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

ARG DOCKER_BASE_IMAGE=rocm/dev-ubuntu-24.04:6.4.3
FROM ${DOCKER_BASE_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

# streak2 hosts can enable kernel FIPS mode even though this Ubuntu image has
# no FIPS provider. Use OpenSSL's default provider for package downloads and
# source builds, matching the GEOS streak2 container setup.
COPY docker/openssl-non-fips.cnf /etc/ssl/openssl-non-fips.cnf
ENV OPENSSL_FORCE_FIPS_MODE=0 \
    OPENSSL_CONF=/etc/ssl/openssl-non-fips.cnf

# Install directory provided as a docker build argument; forwarded via ENV
# (GEOSX_TPL_DIR is part of the image contract consumed by GEOS).
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# ROCm parameters
ARG AMDGPU_TARGET=gfx942
ARG ROCM_VERSION=6.4.3

# Allow changing the number of cores used for building code via spack
ARG SPACK_BUILD_JOBS=4
ENV SPACK_BUILD_JOBS=${SPACK_BUILD_JOBS}

RUN if [ -f /etc/ssl/certs/llnl-ca-bundle.crt ]; then \
      mkdir -p /etc/apt/apt.conf.d && \
      printf '%s\n' \
        'Acquire::https::CaInfo "/etc/ssl/certs/llnl-ca-bundle.crt";' \
        > /etc/apt/apt.conf.d/99-llnl-ca; \
    fi && \
    ln -fs /usr/share/zoneinfo/America/Los_Angeles /etc/localtime && \
    apt-get update

# Packages needed both for the TPL build and for the downstream GEOS build,
# plus the ROCm math libraries GEOS links against.
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wget \
        gnupg \
        ca-certificates \
        gcc-13 \
        g++-13 \
        gfortran-13 \
        libtbb12 \
        libtbbmalloc2 \
        libblas-dev \
        liblapack-dev \
        libz3-dev \
        zlib1g-dev \
        openmpi-bin \
        libopenmpi-dev \
        python3 \
        python3-dev \
        python3-pip \
        python3-sphinx \
        doxygen \
        pkg-config \
        xz-utils \
        gettext \
        bzip2 \
        help2man \
        libtool \
        libgmp-dev \
        unzip \
        libmpfr-dev \
        lbzip2 \
        bzip2 \
        gnupg \
        virtualenv \
        libpugixml-dev \
        roctracer-dev \
        rocsparse-dev \
        rocsolver-dev \
        rocblas-dev \
        hipblas-dev \
        hipsparse-dev \
        hipfft-dev \
        hipsolver-dev \
        hiprand-dev \
        rocprim-dev \
        rocrand-dev \
        rocthrust-dev \
        git && \
    if [ -f /etc/ssl/certs/llnl-ca-bundle.crt ]; then \
      mkdir -p /usr/local/share/ca-certificates && \
      awk 'BEGIN {n=0} /-----BEGIN/ {n++; f=sprintf("/usr/local/share/ca-certificates/llnl-%03d.crt", n)} n>0 {print > f}' \
        /etc/ssl/certs/llnl-ca-bundle.crt && \
      update-ca-certificates ; \
    fi && \
    rm -rf /var/lib/apt/lists/*

# Use Ubuntu's merged trust store for subsequent Python, curl, Git, and pip
# operations after ca-certificates has been installed.
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt

# Install clingo for Spack. Do not upgrade Ubuntu's Debian-managed pip in
# place; Ubuntu 24.04's pip package cannot be uninstalled by pip.
RUN python3 -m pip install clingo --break-system-packages

# The ROCm base image does not ship cmake, so install it here (the geosx base
# images used by the other TPL Dockerfiles provide it already).
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

# OpenMPI hack for Ubuntu and provide amdclang wrappers with the GCC 13 system toolchain.
# Keep ROCm's native clang/clang++ links intact: the amdllvm driver uses those
# companion names internally, so replacing clang++ with a shell wrapper recurses.
RUN ln -sfn /usr/bin /usr/lib/x86_64-linux-gnu/openmpi && \
    printf '%s\n' '#!/bin/sh' "exec /opt/rocm-${ROCM_VERSION}/lib/llvm/bin/amdclang --gcc-toolchain=/usr \"\$@\"" > /usr/local/bin/amdclang-gcc13 && \
    chmod +x /usr/local/bin/amdclang-gcc13 && \
    printf '%s\n' '#!/bin/sh' "exec /opt/rocm-${ROCM_VERSION}/lib/llvm/bin/amdclang++ --gcc-toolchain=/usr \"\$@\"" > /usr/local/bin/amdclang++-gcc13 && \
    chmod +x /usr/local/bin/amdclang++-gcc13

# ----- TPL build stage -----
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR
ARG AMDGPU_TARGET
ARG SPEC

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libtbb-dev \
      make \
      autopoint \
      autotools-dev \
      automake \
      ninja-build \
      bc \
      file \
      patch \
      ca-certificates \
      git && \
    rm -rf /var/lib/apt/lists/*

# Run uberenv. The SPEC is supplied by the matrix, as for the other TPL images.
# Have to create install directory first for uberenv.
# -k flag is to ignore SSL errors.
#
# A background heartbeat prints progress every minute: the ROCm TPL build runs
# for hours and spack is otherwise silent, which makes a stalled build
# indistinguishable from a slow one in CI logs.
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
    mkdir -p ${GEOSX_TPL_DIR} && \
    GEOSX_SPEC="${SPEC}" && \
    if [ -z "${GEOSX_SPEC}" ] || [ "${GEOSX_SPEC}" = "undefined" ]; then \
        echo "ERROR: SPEC build-arg must be supplied" >&2 ; \
        exit 1 ; \
    fi && \
    { \
      ( while true; do \
          sleep 60; \
          echo "[heartbeat] $(date -Iseconds) uberenv/spack still running"; \
          find ${GEOSX_TPL_DIR}/build_stage -maxdepth 2 -mindepth 2 -type d -printf '%T@ %p\n' 2>/dev/null | \
            sort -nr | head -n 3 | \
            while read -r _ path; do \
              echo "[heartbeat] recent stage dir: ${path}"; \
            done; \
          find ${GEOSX_TPL_DIR}/build_stage -maxdepth 4 \( -name spack-build-out.txt -o -name spack-build-env.txt -o -name spack-configure-args.txt \) -printf '%T@ %p\n' 2>/dev/null | \
            sort -nr | head -n 3 | \
            while read -r _ path; do \
              echo "[heartbeat] recent stage file: ${path}"; \
              tail -n 5 "${path}" 2>/dev/null || true; \
              printf '\n'; \
            done; \
          ps -eo pid,ppid,etime,%cpu,%mem,cmd 2>/dev/null | \
            grep -E 'spack|python3|curl|wget|git|cmake|ninja|make|amdclang|gfortran|gcc|g\\+\\+' | \
            grep -v grep | \
            tail -n 20 | \
            cut -c1-240 || true; \
        done ) & \
      hb=$!; \
      ./scripts/uberenv/uberenv.py \
        --spec "${GEOSX_SPEC}" \
        --spack-env-file=${SRC_DIR}/docker/spack-rocm.yaml \
        --project-json=${SRC_DIR}/.uberenv_config.json \
        --prefix ${GEOSX_TPL_DIR} \
        -j ${SPACK_BUILD_JOBS} \
        -k; \
      rc=$?; \
      kill ${hb} 2>/dev/null || true; \
      wait ${hb} 2>/dev/null || true; \
      test ${rc} -eq 0; \
    } && \
    rm -f lvarray* && \
    cp *.cmake /spack-generated.cmake && \
    cd ${GEOSX_TPL_DIR} && \
    rm -rf bin/ build_stage/ builtin_spack_packages_repo/ misc_cache/ spack/ spack_env/ .spack-db/

# ----- Final GEOS-build image -----
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR
# ARGs are scoped per stage, so the ROCm ones must be redeclared here for the
# ENV defaults at the bottom of this stage to interpolate.
ARG AMDGPU_TARGET
ARG ROCM_VERSION

# The non-FIPS OpenSSL configuration is needed while building the TPLs on
# FIPS-enabled hosts, but it must not be inherited by downstream tools. In
# particular, sccache 0.17 uses OpenSSL for its GCS token exchange and this
# configuration makes Ubuntu reject the Google endpoint certificate as too
# weak. The GEOS CI script applies the same configuration at runtime only when
# it is actually needed.
ENV OPENSSL_CONF=""

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR

# Extract the generated host-config
COPY --from=tpl_toolchain /spack-generated.cmake /

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y --no-install-recommends \
    openssh-client \
    ca-certificates \
    curl \
    python3 \
    texlive \
    texlive-latex-extra \
    graphviz \
    libxml2-utils \
    git \
    ghostscript \
    ninja-build \
    python3-dev \
    python3-sphinx \
    python3-mpi4py \
    python3-scipy \
    python3-virtualenv \
    python3-matplotlib \
    python3-venv \
    python3-pytest && \
    rm -rf /var/lib/apt/lists/*

# Install sccache to speed up downstream GEOS builds
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache

# Helpful environment defaults for HIP
ENV ROCM_PATH=/opt/rocm-${ROCM_VERSION}
ENV HIP_PATH=${ROCM_PATH}
ENV PATH=${ROCM_PATH}/bin:${ROCM_PATH}/llvm/bin:${PATH}
ENV LD_LIBRARY_PATH=${ROCM_PATH}/lib:${ROCM_PATH}/lib64:${ROCM_PATH}/llvm/lib
ENV CMAKE_HIP_ARCHITECTURES=${AMDGPU_TARGET}
