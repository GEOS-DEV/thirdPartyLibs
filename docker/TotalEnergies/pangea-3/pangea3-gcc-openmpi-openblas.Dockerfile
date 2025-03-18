#######################################
# Pangea 3 image : gcc - openmpi - openblas
#######################################
#
# Installs :
#   - openmpi  = 4.1.6
#   - openblas = 0.3.18
#   - cuda     = 11.8.0
#
#######################################
#
# Description :
#   - the image is based on onetechssc/pangea3:gcc11.4.0_v1.0 built from pangea3-gcc.Dockerfile
#   - this image is deployed as onetechssc/pangea3:gcc11.4.0-openmpi4.1.6-openblas0.3.18-cuda11.8.0_v1.0
#   - openblas is installed via spack (as done for Pangea 3)
#   - openmpi and cuda are installed via spack (part of system image on Pangea 3)
#
# Usage :
#   build the image:
#   - podman build --format docker -t onetechssc/pangea3:gcc11.4.0-openmpi4.1.6-openblas0.3.18-cuda11.8.0_v1.0 -f pangea3-gcc-openmpi-openblas.Dockerfile -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem  .
#   run the image:
#   - podman run -it --detach --privileged --name pangea3_gcc_openmpi_openblas -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem localhost/onetechssc/pangea3:gcc11.4.0-openmpi4.1.6-openblas0.3.18-cuda11.8.0_v1.0
#   - podman exec -it pangea3_gcc_openmpi_openblas /bin/bash
#   push the image (requires to be part of the onetechssc docker organization):
#   - podman login docker.io
#   - podman push localhost/onetechssc/pangea3:gcc11.4.0-openmpi4.1.6-openblas0.3.18-cuda11.8.0_v1.0 docker://docker.io/onetechssc/pangea3:gcc11.4.0-openmpi4.1.6-openblas0.3.18-cuda11.8.0_v1.0
#
#######################################

# -------------------------------------
# PANGEA3 - GCC-HPCX-MKL
FROM docker.io/onetechssc/pangea3:gcc11.4.0_v1.0 AS pangea3
# ------
# LABELS
LABEL description="Pangea 3 image : gcc - cmake - python - openmpi - openblas - cuda"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG OPENBLAS_VERSION=0.3.18
ARG OPENMPI_VERSION=4.1.6
ARG CUDA_VERSION=11.8.0
# ------
# INSTALL
# spack config (make sure you survive our wonderfull proxy)
RUN spack config --scope defaults add config:connect_timeout:120
RUN spack config --scope defaults add config:url_fetch_method:curl
# openblas (with openmp)
RUN spack install openblas@$OPENBLAS_VERSION threads=openmp %gcc@$GCC_VERSION
# cuda
RUN spack install cuda@$CUDA_VERSION %gcc@$GCC_VERSION
# openmpi
RUN spack install openmpi@$OPENMPI_VERSION +cuda cuda_arch=70 %gcc@$GCC_VERSION
# numpy with openblas
RUN spack install py-numpy %gcc@$GCC_VERSION ^python@$PYTHON_VERSION ^openblas@$OPENBLAS_VERSION
# virtualenv (openssl error when using curl)
RUN spack config --scope defaults add config:url_fetch_method:urllib &&\
    spack install py-virtualenv %gcc@$GCC_VERSION ^python@$PYTHON_VERSION &&\
    spack config --scope defaults add config:url_fetch_method:curl
# sccache
RUN dnf makecache --refresh && dnf -y install cargo openssl-devel  &&\
    cargo install sccache --locked && mkdir -p /opt/sccache/ && cp -r /root/.cargo/bin /opt/sccache/  &&\
    dnf remove -y cargo openssl-devel && dnf clean all
# flex
RUN spack install flex %gcc@$GCC_VERSION
# zlib
RUN spack install zlib %gcc@$GCC_VERSION
# pugixml
RUN spack install pugixml %gcc@$GCC_VERSION
# ------
# ENV
# sccache
ENV SCCACHE=/opt/sccache/bin/sccache
# create env script
RUN <<EOF cat > /root/.setup_env.sh
. /opt/spack/share/spack/setup-env.sh
spack load gcc@$GCC_VERSION python@$PYTHON_VERSION cmake@$CMAKE_VERSION \
           openblas@$OPENBLAS_VERSION openmpi@$OPENMPI_VERSION cuda@$CUDA_VERSION \
           py-numpy py-virtualenv \
           flex zlib
EOF
RUN chmod +x /root/.setup_env.sh