# TPL build Dockerfile for Rocky Linux-based images.
#
# This Dockerfile expects DOCKER_BASE_IMAGE to point at one of the
# geosx/rockylinux:* images produced by
# https://github.com/GEOS-DEV/docker_base_images. Those images already provide:
#   * the toolchain (gcc-toolset-N or clang) under /opt/compiler/bin/, with
#     CC/CXX/FC set
#   * cmake (under /usr/local) and doxygen (when the base PACKAGES include it)
#   * the upstream NVIDIA CUDA toolkit when DOCKER_BASE_IMAGE is a CUDA variant
#
# The CUDA + clang case still wants /usr/local/bin/clang{,++}-gcc<N> wrappers
# so that NVCC's -ccbin doesn't accidentally pull in the system libstdc++.
# We create those wrappers here when both CLANG and a GCC toolset are
# available, but spack.yaml is the system of record for which compiler to use.

# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

ARG DOCKER_BASE_IMAGE=rockylinux:8
FROM ${DOCKER_BASE_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# GCC_VERSION lets the clang+CUDA case wire up clang->gcc-toolset wrappers.
ARG GCC_VERSION

# Packages needed both for the TPL build and for the downstream GEOS build.
# Some Rocky 8 vs 9 differences are handled by the base image already
# (curl vs curl-minimal, etc.); here we only add things the base images
# don't preinstall.
RUN dnf clean all && \
    dnf -y install dnf-plugins-core || true && \
    (dnf config-manager --set-enabled powertools 2>/dev/null || \
     dnf config-manager --set-enabled crb       2>/dev/null || \
     dnf config-manager --set-enabled devel     2>/dev/null || true) && \
    dnf -y install \
        which \
        zlib-devel \
        tbb \
        openmpi \
        openmpi-devel \
        python3-pip \
        unzip \
        mpfr-devel \
        bzip2 \
        gnupg2 \
        xz \
        python3-virtualenv && \
    dnf clean all && rm -rf /var/cache/dnf /var/lib/dnf

# Install clingo for Spack
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install clingo

# Make `mpicc`/`mpicxx` resolve without a `module load` step.
ENV PATH="/usr/lib64/openmpi/bin:${PATH}" \
    MPICC=/usr/lib64/openmpi/bin/mpicc \
    MPICXX=/usr/lib64/openmpi/bin/mpicxx \
    MPIEXEC=/usr/lib64/openmpi/bin/mpirun

# Some downstream builds expect /usr/lib64/openmpi/include to point at the
# headers; on Rocky those live under /usr/include/openmpi-x86_64.
RUN if [ -d /usr/include/openmpi-x86_64 ] && [ ! -e /usr/lib64/openmpi/include ]; then \
        mkdir -p /usr/lib64/openmpi && \
        ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include ; \
    fi && \
    if [ -e /usr/lib64/libblas.so.3 ]   && [ ! -e /usr/lib64/libblas.so   ]; then ln -s /usr/lib64/libblas.so.3   /usr/lib64/libblas.so   ; fi && \
    if [ -e /usr/lib64/liblapack.so.3 ] && [ ! -e /usr/lib64/liblapack.so ]; then ln -s /usr/lib64/liblapack.so.3 /usr/lib64/liblapack.so ; fi

# When both clang and gcc-toolset-${GCC_VERSION} are present (clang+CUDA matrix
# rows), provide wrapper compilers that bake in --gcc-toolchain so NVCC's -ccbin
# resolves correct libstdc++ headers/libs.
RUN if [ -n "${GCC_VERSION}" ] && [ -d "/opt/rh/gcc-toolset-${GCC_VERSION}" ] \
       && command -v clang >/dev/null 2>&1; then \
        printf '%s\n' '#!/usr/bin/env bash' \
            "exec $(command -v clang) --gcc-toolchain=/opt/rh/gcc-toolset-${GCC_VERSION}/root/usr \"\$@\"" \
            > /usr/local/bin/clang-gcc${GCC_VERSION} && \
        chmod +x /usr/local/bin/clang-gcc${GCC_VERSION} && \
        printf '%s\n' '#!/usr/bin/env bash' \
            "exec $(command -v clang++) --gcc-toolchain=/opt/rh/gcc-toolset-${GCC_VERSION}/root/usr \"\$@\"" \
            > /usr/local/bin/clang++-gcc${GCC_VERSION} && \
        chmod +x /usr/local/bin/clang++-gcc${GCC_VERSION} && \
        /usr/local/bin/clang-gcc${GCC_VERSION} --version && \
        /usr/local/bin/clang++-gcc${GCC_VERSION} --version ; \
    fi

# ----- TPL build stage -----
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR
ARG SPEC

RUN dnf -y install \
        tbb-devel \
        bc \
        file \
        patch \
        ca-certificates \
        autoconf \
        automake \
        make \
        m4 \
        git && \
    dnf clean all && rm -rf /var/cache/dnf /var/lib/dnf

# Run uberenv. The SPEC is supplied by the matrix because the spack toolchain
# tag depends on the compiler+version baked into the base image.
#
# We wrap the call in `scl enable gcc-toolset-${GCC_VERSION}` when that toolset
# exists so that build steps invoking `gcc`/`g++` directly find the toolset
# binaries. When the base image's compiler is gcc-toolset, this is harmless;
# when it's a clang+CUDA image with gfortran from the toolset, it ensures
# fortran shared-library paths resolve.
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
    mkdir -p ${GEOSX_TPL_DIR} && \
    GEOSX_SPEC="${SPEC}" && \
    if [ -z "${GEOSX_SPEC}" ] || [ "${GEOSX_SPEC}" = "undefined" ]; then \
        echo "ERROR: SPEC build-arg must be supplied" >&2 ; \
        exit 1 ; \
    fi && \
    if [ -n "${GCC_VERSION}" ] && [ -d "/opt/rh/gcc-toolset-${GCC_VERSION}" ]; then \
        scl enable "gcc-toolset-${GCC_VERSION}" " \
            ./scripts/uberenv/uberenv.py \
                --spec '${GEOSX_SPEC}' \
                --spack-env-file=${SRC_DIR}/docker/rocky-spack.yaml \
                --project-json=${SRC_DIR}/.uberenv_config.json \
                --prefix ${GEOSX_TPL_DIR} \
                -k " ; \
    else \
        ./scripts/uberenv/uberenv.py \
            --spec "${GEOSX_SPEC}" \
            --spack-env-file=${SRC_DIR}/docker/rocky-spack.yaml \
            --project-json=${SRC_DIR}/.uberenv_config.json \
            --prefix ${GEOSX_TPL_DIR} \
            -k ; \
    fi && \
    rm -f lvarray* && \
    cp *.cmake /spack-generated.cmake && \
    cd ${GEOSX_TPL_DIR} && \
    rm -rf bin/ build_stage/ builtin_spack_packages_repo/ misc_cache/ spack/ spack_env/ .spack-db/

# ----- Final GEOS-build image -----
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR
ARG GCC_VERSION
COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR
COPY --from=tpl_toolchain /spack-generated.cmake /

# The clang+gcc-toolset wrappers are referenced from the spack-generated
# host-config in the CUDA+clang variants, so they must exist in the final image.
RUN if [ -n "${GCC_VERSION}" ] && [ -f "/usr/local/bin/clang-gcc${GCC_VERSION}" ]; then \
        echo "Wrappers already present in final stage" ; \
    fi
COPY --from=tpl_toolchain /usr/local/bin/ /usr/local/bin/

RUN dnf -y install \
        openssh-clients \
        ca-certificates \
        curl \
        python3 \
        texlive \
        graphviz \
        ninja-build \
        git && \
    dnf clean all && rm -rf /var/cache/dnf /var/lib/dnf && \
    if [ -d /usr/include/openmpi-x86_64 ] && [ ! -e /usr/lib64/openmpi/include ]; then \
        mkdir -p /usr/lib64/openmpi && \
        ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include ; \
    fi && \
    if [ -e /usr/lib64/libblas.so.3 ]   && [ ! -e /usr/lib64/libblas.so   ]; then ln -s /usr/lib64/libblas.so.3   /usr/lib64/libblas.so   ; fi && \
    if [ -e /usr/lib64/liblapack.so.3 ] && [ ! -e /usr/lib64/liblapack.so ]; then ln -s /usr/lib64/liblapack.so.3 /usr/lib64/liblapack.so ; fi

# Install sccache to speed up downstream GEOS builds
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache
