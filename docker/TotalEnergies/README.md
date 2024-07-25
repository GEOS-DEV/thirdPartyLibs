# TotalEnergies Dockerfiles

## Overview

This directory contains several Dockerfiles used for building and deploying the TPLs.
Below is a table summarizing the purpose and key characteristics of each Dockerfile.

| Dockerfile                               | Description                                                                  | Base Image                    | Key Components Installed                                                                             |
|------------------------------------------|------------------------------------------------------------------------------|-------------------------------|------------------------------------------------------------------------------------------------------|
| `pecan-gcc-openmpi-mkl-cuda.Dockerfile`  | Builds a toolchain with GCC, OpenMPI, CUDA, and Intel MKL for GEOS on Pecan. | `centos:7.7.1908`             | GCC, OpenMPI, CUDA, Intel MKL, numactl-devel, ca-certificates, curl, Python3, zlib-devel             |
| `tpl-pecan.Dockerfile`                   | Builds third-party libraries for GEOS on Pecan environment.                  | `pecan-gcc-openmpi-mkl-cuda`  | CMake, make, bc, file, bison, flex, patch, openssh-clients, texlive, graphviz, libxml2, git, sccache |
| `pangea4-gcc.Dockerfile`                 | Builds a toolchain with GCC, CMake and Python on Pangea 4.                   | `spack/centos-stream`         | GCC, CMake, Python, Wget                                                                             |
| `pangea4-gcc-hpcxompi-onemkl.Dockerfile` | Builds a toolchain with GCC, HPCXOMPI and ONEMKL on Pangea 4.                | `pangea4-gcc`                 | GCC, CMake, Python, Wget, HPCXOMPI, ONEMKL                                                           |
| `tpl-pangea4.Dockerfile`                 | Builds third-party libraries for GEOS on Pangea 4 environment.               | `pangea4-gcc-hpcxompi-onemkl` | GCC, CMake, Python, Wget, HPCXOMPI, ONEMKL, sccache                                                  |

## DockerHub

The Docker images built from the ${cluster}.Dockerfile are available on DockerHub under the `onetechssc` organization for:
  - pangea4 cluster : [onetechssc/pangea4](https://hub.docker.com/r/onetechssc/pangea4)
