# syntax=docker/dockerfile:1.4

#######################################
# Pangea 4 image : gcc - cmake - python
#######################################
#
# Installs :
#   - gcc    = 12.1
#   - cmake  = 3.27.9
#   - python = 3.11
#
#######################################
#
# Description :
#   - the image is based on spack/centos-stream:latest (CentOS Stream 8 image with spack installed)
#   - this image is deployed as onetechssc/pangea4:gcc12.1_v1.0
#   - gcc, cmake, python and wget are installed via spack (as done for Pangea 4)
#
# Usage :
#   build the image:
#   - podman build --format docker -t onetechssc/pangea4:gcc12.1_v1.0 -f pangea4-gcc.Dockerfile -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem  .
#   run the image:
#   - podman run -it --detach --privileged --name pangea4_gcc -v /etc/pki/ca-trust/extracted/pem/:/etc/pki/ca-trust/extracted/pem localhost/onetechssc/pangea4:gcc12.1_v1.0
#   - podman exec -it pangea4_gcc /bin/bash
#   push the image (requires to be part of the onetechssc docker organization):
#   - podman login docker.io
#   - podman push localhost/onetechssc/pangea4:gcc12.1_v1.0 docker://docker.io/onetechssc/pangea4:gcc12.1_v1.0
#
#######################################

# -------------------------------------
# PANGEA4 - BASE [GCC - CMAKE - PYTHON]
# install tools via spack for linux/x86_64 architecture and redhat8 platform
FROM --platform=linux/x86_64 docker.io/spack/centos-stream:latest AS pangea4-base
# ------
# LABELS
LABEL description="Pangea 4 image : gcc - cmake - python"
LABEL version="1.0"
LABEL maintainer="TotalEnergies HPC Team"
# ------
# ARGS
ARG GCC_VERSION=12.1
ARG CMAKE_VERSION=3.27.9
ARG PYTHON_VERSION=3.11
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