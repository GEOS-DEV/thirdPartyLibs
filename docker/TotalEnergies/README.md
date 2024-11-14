# TotalEnergies Dockerfiles

## Overview

This directory contains several Dockerfiles used for building and deploying the TPLs.
Below is a table summarizing the purpose and key characteristics of each Dockerfile.

| Dockerfile                               | Description                                                                   | Base Image                    | Key Components Installed                                             |
|------------------------------------------|-------------------------------------------------------------------------------|-------------------------------|----------------------------------------------------------------------|
| `pangea3-gcc-openmpi-openblas.Dockerfile`| Builds a toolchain with GCC, OpenMPI, CUDA, and OpenBLAS for GEOS on Pangea 3.| `ppc64le/almalinux:8`         | GCC, OpenMPI, CUDA, OpenBLAS, CMake, Python3.8                       |
| `pangea3-tpl.Dockerfile`                 | Builds third-party libraries for GEOS on Pangea 3 environment.                | `pangea3-gcc-openmpi-openblas`| GCC, OpenMPI, CUDA, OpenBLAS, CMake, Python3.8, TPLs                 |
| `pangea4-gcc.Dockerfile`                 | Builds a toolchain with GCC, CMake and Python on Pangea 4.                    | `spack/centos-stream`         | GCC, CMake, Python3.11, Wget                                         |
| `pangea4-gcc-hpcxompi-onemkl.Dockerfile` | Builds a toolchain with GCC, HPCXOMPI and ONEMKL on Pangea 4.                 | `pangea4-gcc`                 | GCC, CMake, Python3.11, Wget, HPCXOMPI, ONEMKL                       |
| `pangea4-tpl.Dockerfile`                 | Builds third-party libraries for GEOS on Pangea 4 environment.                | `pangea4-gcc-hpcxompi-onemkl` | GCC, CMake, Python3.11, Wget, HPCXOMPI, ONEMKL, ninja, sccache, TPLs |

## DockerHub

The Docker images built from the ${cluster}.Dockerfile are available on DockerHub under for:
  - pangea3 cluster : [7g8efcehpff/pangea-almalinux8-gcc9.4-openmpi4.1.2-cuda11.5.0-openblas0.3.18](https://hub.docker.com/r/7g8efcehpff/pangea-almalinux8-gcc9.4-openmpi4.1.2-cuda11.5.0-openblas0.3.18), will move to onetechssc/pangea3 once newer version of gcc is available.
  - pangea4 cluster : [onetechssc/pangea4](https://hub.docker.com/r/onetechssc/pangea4)
