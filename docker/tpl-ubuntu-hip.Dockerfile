# NOTE: see docker/tpl-ubuntu-gcc.Dockerfile for detailed comments
ARG TMP_DIR=/tmp
ARG SRC_DIR=$TMP_DIR/thirdPartyLibs
ARG BLD_DIR=$TMP_DIR/build

# Base image is set by workflow via DOCKER_ROOT_IMAGE
ARG DOCKER_ROOT_IMAGE=rocm/dev-ubuntu-24.04:6.4.3

FROM ${DOCKER_ROOT_IMAGE} AS tpl_toolchain_intersect_geosx_toolchain
ARG SRC_DIR

ARG INSTALL_DIR
ENV GEOSX_TPL_DIR=$INSTALL_DIR

# Parameters
ARG AMDGPU_TARGET=gfx942
ARG ROCM_VERSION=6.4.3

# Allow changing the number of cores used for building code via spack
ARG SPACK_BUILD_JOBS=4
ENV SPACK_BUILD_JOBS=${SPACK_BUILD_JOBS}

RUN ln -fs /usr/share/zoneinfo/America/Los_Angeles /etc/localtime && \
    apt-get update

# Install system packages
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        wget \
        gnupg \
        ca-certificates \
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
        bison \
        flex \
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
    rm -rf /var/lib/apt/lists/*

# Install clingo for Spack (use pip without upgrading pip to avoid Debian conflict)
RUN python3 -m pip install clingo --break-system-packages

# Install CMake
RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-cmake.sh

# OpenMPI hack for Ubuntu and expose ROCm LLVM as the expected clang path.
RUN ln -s /usr/bin /usr/lib/x86_64-linux-gnu/openmpi && \
    ln -s /opt/rocm-${ROCM_VERSION}/lib/llvm/bin/clang /usr/bin/clang && \
    ln -s /opt/rocm-${ROCM_VERSION}/lib/llvm/bin/clang++ /usr/bin/clang++

# MPI environment variables
ENV CC=/usr/bin/amdclang \
    CXX=/usr/bin/amdclang++ \
    MPICC=/usr/bin/mpicc \
    MPICXX=/usr/bin/mpicxx \
    MPIEXEC=/usr/bin/mpirun \
    OMPI_CC=/usr/bin/amdclang \
    OMPI_CXX=/usr/bin/amdclang++

# Installing TPLs
FROM tpl_toolchain_intersect_geosx_toolchain AS tpl_toolchain
ARG SRC_DIR
ARG BLD_DIR

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

# Run uberenv
# Have to create install directory first for uberenv
# -k flag is to ignore SSL errors
# --spack-debug to debug build
RUN --mount=src=.,dst=$SRC_DIR,readwrite cd ${SRC_DIR} && \
     mkdir -p ${GEOSX_TPL_DIR} && \
     python3 - <<'PY' && \
from pathlib import Path

base = Path("/tmp/thirdPartyLibs/docker/spack.yaml").read_text()
replacements = {
    "# __ROCM_TOOLCHAIN__": """    amdclang-19:
      - spec: '%[virtuals=c]llvm-amdgpu@6.4.3'
        when: '%c'
      - spec: '%[virtuals=cxx]llvm-amdgpu@6.4.3'
        when: '%cxx'
      - spec: '%[virtuals=fortran]gcc@13.3.0'
        when: '%fortran'
      - spec: '%openmpi@4.1.2'
        when: '%mpi'""",
    "# __ROCM_COMPILERS__": """    llvm-amdgpu:
      buildable: false
      externals:
      - spec: llvm-amdgpu@6.4.3
        prefix: /usr
        extra_attributes:
          compilers:
            c: /usr/bin/amdclang
            cxx: /usr/bin/amdclang++""",
    "# __ROCM_PACKAGES__": """    hip:
      buildable: false
      externals:
      - spec: hip@6.4.3
        prefix: /opt/rocm-6.4.3
    rocprim:
      buildable: false
      externals:
      - spec: rocprim@6.4.3
        prefix: /opt/rocm-6.4.3
    rocsparse:
      buildable: false
      externals:
      - spec: rocsparse@6.4.3
        prefix: /opt/rocm-6.4.3
    roctracer:
      buildable: false
      externals:
      - spec: roctracer@6.4.3
        prefix: /opt/rocm-6.4.3
    rocblas:
      buildable: false
      externals:
      - spec: rocblas@6.4.3
        prefix: /opt/rocm-6.4.3
    rocrand:
      buildable: false
      externals:
      - spec: rocrand@6.4.3
        prefix: /opt/rocm-6.4.3
    rocsolver:
      buildable: false
      externals:
      - spec: rocsolver@6.4.3
        prefix: /opt/rocm-6.4.3
    rocthrust:
      buildable: false
      externals:
      - spec: rocthrust@6.4.3
        prefix: /opt/rocm-6.4.3
    hipblas:
      buildable: false
      externals:
      - spec: hipblas@6.4.3 +rocm
        prefix: /opt/rocm-6.4.3
    hipsparse:
      buildable: false
      externals:
      - spec: hipsparse@6.4.3 +rocm
        prefix: /opt/rocm-6.4.3
    hipfft:
      buildable: false
      externals:
      - spec: hipfft@6.4.3 +rocm
        prefix: /opt/rocm-6.4.3
    hipsolver:
      buildable: false
      externals:
      - spec: hipsolver@6.4.3 +rocm
        prefix: /opt/rocm-6.4.3
    hiprand:
      buildable: false
      externals:
      - spec: hiprand@6.4.3 +rocm
        prefix: /opt/rocm-6.4.3
    rocm-device-libs:
      buildable: false
      externals:
      - spec: rocm-device-libs@6.4.3
        prefix: /opt/rocm-6.4.3
    hsa-rocr-dev:
      buildable: false
      externals:
      - spec: hsa-rocr-dev@6.4.3
        prefix: /opt/rocm-6.4.3""",
    "# __ROCM_OPENMPI_EXTERNAL__": """      - spec: openmpi@4.1.2 %llvm-amdgpu@6.4.3
        prefix: /usr/lib/x86_64-linux-gnu/openmpi""",
}

for marker, replacement in replacements.items():
    if marker not in base:
        raise SystemExit(f"missing marker: {marker}")
    base = base.replace(marker, replacement)

Path("/tmp/spack-rocm.yaml").write_text(base)
PY
     && \
     test -f /tmp/spack-rocm.yaml && \
     ./scripts/uberenv/uberenv.py \
       --spec "+rocm~uncrustify~openmp~pygeosx~trilinos~petsc amdgpu_target=${AMDGPU_TARGET} %amdclang-19 ^caliper~papi~gotcha~sampler~libunwind~libdw" \
       --spack-env-file=/tmp/spack-rocm.yaml \
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

# Extract only TPLs from previous stage
FROM tpl_toolchain_intersect_geosx_toolchain AS geosx_toolchain
ARG SRC_DIR

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

RUN --mount=src=.,dst=$SRC_DIR $SRC_DIR/docker/install-sccache.sh
ENV SCCACHE=/opt/sccache/bin/sccache

# Helpful environment defaults for HIP
ENV ROCM_PATH=/opt/rocm-${ROCM_VERSION}
ENV HIP_PATH=${ROCM_PATH}/hip
ENV PATH=${ROCM_PATH}/bin:${ROCM_PATH}/llvm/bin:${PATH}
ENV LD_LIBRARY_PATH=${ROCM_PATH}/lib:${ROCM_PATH}/lib64:${ROCM_PATH}/llvm/lib
ENV CMAKE_HIP_ARCHITECTURES=${AMDGPU_TARGET}
