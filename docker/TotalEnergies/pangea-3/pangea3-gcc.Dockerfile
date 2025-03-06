# syntax=docker/dockerfile:1.4

#######################################
# Pangea 3 image : gcc - cmake - python
#######################################
#
# Installs :
#   - gcc    = 11.4.0
#   - cmake  = 3.27.9
#   - python = 3.11.7
#
#######################################
#
# Description :
#   - the image is based on spack/almalinux8:latest (Almalinux 8 image with spack installed)
#   - this image is deployed as onetechssc/pangea3:gcc11.4.0_v1.0
#   - gcc, cmake, python and wget are installed via spack (as done for Pangea 3)
#
# Usage :
#   build the image:
#   - podman build --format docker -t onetechssc/pangea3:gcc11.4.0_v1.0 -f pangea3-gcc.Dockerfile -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem  .
#   run the image:
#   - podman run -it --detach --privileged --name pangea3_gcc -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem localhost/onetechssc/pangea3:gcc11.4.0_v1.0
#   - podman exec -it pangea3_gcc /bin/bash
#   push the image (requires to be part of the onetechssc docker organization):
#   - podman login docker.io
#   - podman push localhost/onetechssc/pangea3:gcc11.4.0_v1.0 docker://docker.io/onetechssc/pangea3:gcc11.4.0_v1.0
#
#######################################

# -------------------------------------
# PANGEA3 - BASE [GCC - CMAKE - PYTHON]
# install tools via spack for linux/ppc64le architecture and almalinux platform
FROM --platform=linux/ppc64le docker.io/spack/almalinux8:latest AS pangea3-base
# ------
# LABELS
LABEL description="Pangea 3 image : gcc - cmake - python"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG GCC_VERSION=11.4.0
ARG CMAKE_VERSION=3.27.9
ARG PYTHON_VERSION=3.11.7
# ------
# INSTALL
# spack config (make sure you survive our wonderfull proxy)
RUN spack config --scope defaults add config:connect_timeout:120
RUN spack config --scope defaults add config:url_fetch_method:curl
# gcc
RUN spack install gcc@$GCC_VERSION
RUN . /opt/spack/share/spack/setup-env.sh &&\
    spack load gcc@$GCC_VERSION &&\
    spack compiler find
# python
RUN spack install python@$PYTHON_VERSION %gcc@$GCC_VERSION
# cmake (openssl error when using curl)
RUN spack config --scope defaults add config:url_fetch_method:urllib &&\
    spack install cmake@$CMAKE_VERSION %gcc@$GCC_VERSION &&\
    spack config --scope defaults add config:url_fetch_method:curl
# wget
RUN spack install wget %gcc@$GCC_VERSION
# ------
# ENV
ENV GCC_VERSION=${GCC_VERSION}
ENV CMAKE_VERSION=${CMAKE_VERSION}
ENV PYTHON_VERSION=${PYTHON_VERSION}