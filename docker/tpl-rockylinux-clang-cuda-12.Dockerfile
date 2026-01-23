# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

FROM nvidia/cuda:12.9.1-devel-rockylinux8 AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR
ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Installing dependencies
RUN dnf clean all && \
    dnf -y update && \
    dnf -y install dnf-plugins-core && \
    dnf config-manager --set-enabled powertools || dnf config-manager --set-enabled devel && \
    dnf -y install \
        which \
        clang-17.0.6 \
        gcc-toolset-13 \
        python3 \
        zlib-devel \
        tbb \
        blas \
        lapack \
        openmpi \
        openmpi-devel \
        python3-pip \
        unzip \
        mpfr-devel \
        bzip2 \
        gnupg \
        xz \
        python3-virtualenv

# Install clingo for Spack
RUN python3 -m pip install --upgrade pip && \
    python3 -m pip install clingo

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

# Installing TPL's
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

RUN dnf -y install \
        tbb-devel \
        bc \
        file \
        patch \
        ca-certificates \
        autoconf \
        automake \
        m4 \
        git

# RUN uberenv
# 1. We wrap this in 'scl enable gcc-toolset-13' so the build finds GCC 13 headers.
# 2. We pass --gcc-toolchain to Clang via CXXFLAGS to prevent the 'extern C' linkage error.
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOSX_TPL_DIR} && \
     ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include && \
     ln -s /usr/lib64/libblas.so.3 /usr/lib64/libblas.so && \
     ln -s /usr/lib64/liblapack.so.3 /usr/lib64/liblapack.so && \
     scl enable gcc-toolset-13 ' \
     # Create clang wrappers that always use gcc-toolset-13 for libstdc++ headers/libs.
     # This is critical for CUDA builds where NVCC invokes the host compiler via -ccbin
     # and does not reliably forward --gcc-toolchain from CXXFLAGS/CMAKE_CXX_FLAGS.
     cat > /usr/local/bin/clang-gcc13 <<\"EOF\" && \
#!/usr/bin/env bash
exec /usr/bin/clang --gcc-toolchain=/opt/rh/gcc-toolset-13/root/usr \"$@\"
EOF
     chmod +x /usr/local/bin/clang-gcc13 && \
     cat > /usr/local/bin/clang++-gcc13 <<\"EOF\" && \
#!/usr/bin/env bash
exec /usr/bin/clang++ --gcc-toolchain=/opt/rh/gcc-toolset-13/root/usr \"$@\"
EOF
     chmod +x /usr/local/bin/clang++-gcc13 && \
     export CXXFLAGS="--gcc-toolchain=/opt/rh/gcc-toolset-13/root/usr" && \
     export CFLAGS="--gcc-toolchain=/opt/rh/gcc-toolset-13/root/usr" && \
     ./scripts/uberenv/uberenv.py \
       --spec "+cuda~uncrustify~openmp~pygeosx cuda_arch=70 %clang-17 ^cuda@12.9.1+allow-unsupported-compilers ^caliper~gotcha~sampler~libunwind~libdw~papi" \
       --spack-env-file=${SRC_DIR}/docker/rocky-spack.yaml \
       --project-json=.uberenv_config.json \
       --prefix ${GEOSX_TPL_DIR} \
       -k ' && \
     rm -f lvarray* && \
     cp *.cmake /spack-generated.cmake && \
     cd ${GEOSX_TPL_DIR} && \
     rm -rf bin/ build_stage/ builtin_spack_packages_repo/ misc_cache/ spack/ spack_env/ .spack-db/

# Extract only TPL's from the previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR
COPY --from=tpl_toolchain /spack-generated.cmake /

RUN dnf clean all && \
    rm -rf /var/cache/dnf && \
    dnf -y install \
        openssh-clients \
        ca-certificates \
        curl \
        python3 \
        texlive \
        graphviz \
        ninja-build \
        git && \
    ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include && \
    ln -s /usr/lib64/libblas.so.3 /usr/lib64/libblas.so && \
    ln -s /usr/lib64/liblapack.so.3 /usr/lib64/liblapack.so

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache