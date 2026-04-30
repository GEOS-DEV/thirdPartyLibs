# TPL build Dockerfile for Rocky Linux-based images.
#
# This Dockerfile expects DOCKER_BASE_IMAGE to point at one of the
# geosx/rockylinux:* images produced by
# https://github.com/GEOS-DEV/docker_base_images. Those images already provide:
#   * the toolchain (gcc-toolset-N or clang) under /opt/compiler/bin/, with
#     CC/CXX/FC set
#   * cmake (under /usr/local)
#   * the upstream NVIDIA CUDA toolkit when DOCKER_BASE_IMAGE is a CUDA variant
#
# Temporary local variables dedicated to the TPL build
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

ARG DOCKER_BASE_IMAGE=rockylinux:8
FROM ${DOCKER_BASE_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

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
        doxygen \
        openmpi \
        openmpi-devel \
        python3-pip \
        unzip \
        mpfr-devel \
        bzip2 \
        gnupg2 \
        perl \
        xz && \
    (dnf -y install python3-virtualenv || \
     /usr/bin/python3 -m pip install --no-cache-dir virtualenv) && \
    dnf clean all && rm -rf /var/cache/dnf /var/lib/dnf

# Install clingo for Spack
RUN (/usr/bin/python3 -m pip --version >/dev/null 2>&1 || \
     /usr/bin/python3 -m ensurepip --upgrade || \
     (dnf -y install python3.12-pip || dnf -y install python3-pip)) && \
    /usr/bin/python3 -m pip install --upgrade pip && \
    /usr/bin/python3 -m pip install clingo

# Make `mpicc`/`mpicxx` resolve without a `module load` step.
ENV PATH="/usr/lib64/openmpi/bin:${PATH}" \
    MPICC=/usr/lib64/openmpi/bin/mpicc \
    MPICXX=/usr/lib64/openmpi/bin/mpicxx \
    MPIEXEC=/usr/lib64/openmpi/bin/mpirun
ENV OMPI_CC=${CC} \
    OMPI_CXX=${CXX}

# Some downstream builds expect /usr/lib64/openmpi/include to point at the
# headers; on Rocky those live under /usr/include/openmpi-x86_64.
RUN if [ -d /usr/include/openmpi-x86_64 ] && [ ! -e /usr/lib64/openmpi/include ]; then \
        mkdir -p /usr/lib64/openmpi && \
        ln -s /usr/include/openmpi-x86_64 /usr/lib64/openmpi/include ; \
    fi && \
    if [ -e /usr/lib64/libblas.so.3 ]   && [ ! -e /usr/lib64/libblas.so   ]; then ln -s /usr/lib64/libblas.so.3   /usr/lib64/libblas.so   ; fi && \
    if [ -e /usr/lib64/liblapack.so.3 ] && [ ! -e /usr/lib64/liblapack.so ]; then ln -s /usr/lib64/liblapack.so.3 /usr/lib64/liblapack.so ; fi

# Rocky OpenMPI defaults wrappers to gcc/g++. For clang-based base images we
# retarget the wrappers to clang/clang++ so mpi wrapper compilers are aligned
# with the image toolchain contract.
RUN if echo "${CC:-}" | grep -q "clang"; then \
        for f in /usr/share/openmpi/mpicc-wrapper-data.txt /usr/share/openmpi/mpicc.openmpi-wrapper-data.txt; do \
            if [ -f "${f}" ]; then sed -i "s|^compiler=.*$|compiler=${CC}|" "${f}" ; fi ; \
        done && \
        for f in /usr/share/openmpi/mpic++-wrapper-data.txt /usr/share/openmpi/mpic++.openmpi-wrapper-data.txt /usr/share/openmpi/mpicxx-wrapper-data.txt /usr/share/openmpi/mpicxx.openmpi-wrapper-data.txt /usr/share/openmpi/mpiCC-wrapper-data.txt /usr/share/openmpi/mpiCC.openmpi-wrapper-data.txt; do \
            if [ -f "${f}" ]; then sed -i "s|^compiler=.*$|compiler=${CXX}|" "${f}" ; fi ; \
        done && \
        mpicc --showme:command && \
        mpic++ --showme:command ; \
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
# GCC toolset rows wrap the build in `scl enable gcc-toolset-${GCC_VERSION}` so
# direct compiler invocations resolve to that toolset. Clang rows do not enable
# the GCC toolset; their generated Spack config leaves GCC available only as
# the explicit Fortran compiler.
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
    mkdir -p ${GEOSX_TPL_DIR} && \
    GEOSX_SPEC="${SPEC}" && \
    if [ -z "${GEOSX_SPEC}" ] || [ "${GEOSX_SPEC}" = "undefined" ]; then \
        echo "ERROR: SPEC build-arg must be supplied" >&2 ; \
        exit 1 ; \
    fi && \
    GEOSX_SPACK_ENV_FILE=${SRC_DIR}/docker/rocky-spack.yaml && \
    if echo "${CC:-}" | grep -q "clang"; then \
        GEOSX_SPACK_ENV_FILE=/tmp/geosx-rocky-spack.yaml && \
        cp ${SRC_DIR}/docker/rocky-spack.yaml ${GEOSX_SPACK_ENV_FILE} && \
        sed -i -E "s/gcc@([0-9]+) languages:='c,c\\+\\+,fortran'/gcc@\\1 languages:='fortran'/g" ${GEOSX_SPACK_ENV_FILE} && \
        sed -i -E '/c: \/opt\/rh\/gcc-toolset-[0-9]+\/root\/usr\/bin\/gcc$/d; /cxx: \/opt\/rh\/gcc-toolset-[0-9]+\/root\/usr\/bin\/g\+\+$/d' ${GEOSX_SPACK_ENV_FILE} ; \
    fi && \
    if [ -n "${GCC_VERSION}" ] && [ -d "/opt/rh/gcc-toolset-${GCC_VERSION}" ] && ! echo "${CC:-}" | grep -q "clang"; then \
        scl enable "gcc-toolset-${GCC_VERSION}" " \
            ./scripts/uberenv/uberenv.py \
                --spec '${GEOSX_SPEC}' \
                --spack-env-file=${GEOSX_SPACK_ENV_FILE} \
                --project-json=${SRC_DIR}/.uberenv_config.json \
                --prefix ${GEOSX_TPL_DIR} \
                -k " ; \
    else \
        ./scripts/uberenv/uberenv.py \
            --spec "${GEOSX_SPEC}" \
            --spack-env-file=${GEOSX_SPACK_ENV_FILE} \
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
COPY --from=tpl_toolchain $GEOSX_TPL_DIR $GEOSX_TPL_DIR
COPY --from=tpl_toolchain /spack-generated.cmake /

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
