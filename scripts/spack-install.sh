#!/bin/bash

CLUSTER=$1
SYS_TYPE=$2
NPROCS=$3

source spack/share/spack/setup-env.sh
spack env create ${CLUSTER}-${SYS_TYPE} spack-environments/${CLUSTER}-${SYS_TYPE}/spack.yaml
spack env activate ${CLUSTER}-${SYS_TYPE}
spack install -j $NPROCS
