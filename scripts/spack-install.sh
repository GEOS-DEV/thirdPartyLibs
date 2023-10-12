#!/bin/bash

SPACK_DIR=$1
CLUSTER=$2
SYS_TYPE=$3
NPROCS=$4

source spack/share/spack/setup-env.sh
spack env create ${CLUSTER}-${SYS_TYPE} spack-environments/${CLUSTER}-${SYS_TYPE}/spack.yaml
spack env activate ${CLUSTER}-${SYS_TYPE}
spack install -j ${NPROCS}
despacktivate