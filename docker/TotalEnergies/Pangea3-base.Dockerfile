# This Dockerfile is used to build a docker image reproducing the Pangea installation over a ppc64le architecture:
# It is not directly callable by the TPL ci but the built image is.

 
# syntax=docker/dockerfile:1
FROM almalinux:8

# copy pangea tree for modules needed by TPLs
COPY ./tarball/liblustreapi.so.1 /lib64/

# export environment variables
## CMake
ADD ./tarball/cmake-*.tgz /

ENV PATH="/data_local/appli_local/MTS/GEOSX/cmake/3.26.4/bin:${PATH}"

## gcc
ADD ./tarball/gcc-*.tgz /

ENV CPATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v/include:${CPATH}" \
    LD_LIBRARY_PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le  /gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v/lib:${LD_LIBRARY_PATH}" \
    LD_LIBRARY_PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v/lib64:${LD_LIBRARY_PATH}" \
    LD_RUN_PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v/lib:${LD_RUN_PATH}" \
    LD_RUN_PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v/lib64:${LD_RUN_PATH}" \
    MANPATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v/share/man:${MANPATH}" \
    PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v/bin:${PATH}" \
   CC=gcc \
   CXX=g++ \
   F77=gfortran \
   F90=gfortran \
   FC=gfortran \
   GCC_ROOT=/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-8.4.1/gcc-9.4.0-xe5cqnyajaqz75up3gflln5zlj2rue5v

## ompi
ADD ./tarball/ompi-*.tgz /

ENV CPATH="/data_local/sw/openmpi/4.1.2/env/gcc-8.4.1/include:${CPATH}" \
    LD_LIBRARY_PATH="/data_local/sw/openmpi/4.1.2/env/gcc-8.4.1/lib:${LD_LIBRARY_PATH}" \
    MANPATH="/data_local/sw/openmpi/4.1.2/env/gcc-8.4.1/share/man:${MANPATH}" \
    PATH="/data_local/sw/openmpi/4.1.2/env/gcc-8.4.1/bin:${PATH}" \
    MPI_ROOT="/data_local/sw/openmpi/4.1.2/env/gcc-8.4.1" \
    OMPI_CC="gcc" \
    OMPI_CXX="g++" \
    OMPI_F77="gfortran" \
    OMPI_F90="gfortran" \
    OMPI_FC="gfortran" \
    OPAL_PREFIX="/data_local/sw/openmpi/4.1.2/env/gcc-8.4.1" \
    OMPI_MCA_btl="self,vader,openib" \
    OMPI_MCA_btl_openib_allow_ib="true" \
    OMPI_MCA_btl_openib_warn_default_gid_prefix="0"

## Cuda
ADD ./tarball/cuda-*.tgz /

ENV CPATH="/data_local/sw/cuda/11.5.0/include:${CPATH}" \
    LIBRARY_PATH="/data_local/sw/cuda/11.5.0/lib64/stubs:${LIBRARY_PATH}" \
    LIBRARY_PATH="/data_local/sw/cuda/11.5.0/lib64:${LIBRARY_PATH}" \
    LD_LIBRARY_PATH="/data_local/sw/cuda/11.5.0/lib64:${LD_LIBRARY_PATH}" \
    LD_RUN_PATH="/data_local/sw/cuda/11.5.0/lib64:${LD_RUN_PATH}" \
    MANPATH="/data_local/sw/cuda/11.5.0/doc/man:${MANPATH}" \
    PATH="/data_local/sw/cuda/11.5.0/bin:${PATH}" \
    CUBLAS_ROOT="/data_local/sw/cuda/11.5.0" \
    CUDA_HOME="/data_local/sw/cuda/11.5.0" \
    CUDA_PATH="/data_local/sw/cuda/11.5.0" \
    CUDA_ROOT="/data_local/sw/cuda/11.5.0" \
    CUDA_VERSION="11.5" \
    PATH="/data_local/sw/cuda/11.5.0/samples/bin/ppc64le/linux/release:${PATH}" \
    CPATH="/data_local/sw/cuda/11.5.0/extras/CUPTI/include:${CPATH}" \
    LIBRARY_PATH="/data_local/sw/cuda/11.5.0/extras/CUPTI/lib64:${LIBRARY_PATH}" \
    LD_LIBRARY_PATH="/data_local/sw/cuda/11.5.0/extras/CUPTI/lib64:${LD_LIBRARY_PATH}" \
    NVHPC_CUDA_HOME="/data_local/sw/cuda/11.5.0"

## Openblas
ADD ./tarball/openblas-*.tgz /

ENV LD_LIBRARY_PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-9.4.0/openblas-0.3.18-vk36pzksytuhylqesg4cca7667np5sjp/lib:${LD_LIBRARY_PATH}" \
   LIBRARY_PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-9.4.0/openblas-0.3.18-vk36pzksytuhylqesg4cca7667np5sjp/lib:${LIBRARY_PATH}" \
    PATH="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-9.4.0/openblas-0.3.18-vk36pzksytuhylqesg4cca7667np5sjp/bin:${PATH}" \
    OPENBLAS_ROOT="/data_local/sw/spack/0.17.0/opt/spack/linux-rhel8-power9le/gcc-9.4.0/openblas-0.3.18-vk36pzksytuhylqesg4cca7667np5sjp"

## lsf
ADD ./tarball/lsf-*.tgz /

ENV LD_LIBRARY_PATH="/data_local/sw/lsf/10.1/linux3.10-glibc2.17-ppc64le/lib:${LD_LIBRARY_PATH}" \
    PATH="/data_local/sw/lsf/10.1/linux3.10-glibc2.17-ppc64le/etc:/data_local/sw/lsf/10.1/linux3.10-glibc2.17-ppc64le/bin:${PATH}"

# Install other needed packages
RUN dnf install -y \
    # gcc deps \
    libmpc-devel.ppc64le glibc-devel \
    # mpirun deps  \
    librdmacm hwloc \
    git git-lfs \
    python38-devel \
    zlib-devel \
    make \
    bc \
    file \
    # Scotch deps \
    bison \
    flex \
    # vtk deps \
    patch && \
    git-lfs install && alternatives --set python /usr/bin/python3 

# Uncomment the two following lines to test the TPLs build
#
# RUN git clone  https://github.com/GEOS-DEV/thirdPartyLibs.git && \
#    cd thirdPartyLibs && git submodule init && git submodule update

# RUN cd thirdPartyLibs && python scripts/config-build.py \
#    --hostconfig=host-configs/TOTAL/pangea3-gcc8.4.1-openmpi-4.1.2.cmake \
#    --buildtype=Release --installpath=/home/tpls-Release -DNUM_PROC=8 && \
#    make -C build-pangea3-gcc8.4.1-openmpi-4.1.2-release -j

# Install tools needed by geos
RUN dnf -y --enablerepo=powertools install \
    ninja-build \
    openssh-clients \
    texlive \
    graphviz \
    libxml2

# build sccache from source as prebuilt binary is not available for current archi / OS couple
RUN dnf makecache --refresh && dnf -y install cargo openssl-devel
RUN cargo install sccache --locked && mkdir -p /opt/sccache/ && cp -r /root/.cargo/bin /opt/sccache/
RUN dnf remove -y cargo openssl-devel
