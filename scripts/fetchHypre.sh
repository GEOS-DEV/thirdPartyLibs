#!/bin/bash

# Input argument: hypre branch
VERSION=${1:-"master"}

# Local variables
BASE_DIR=$(pwd)
HYPRE_DIR=${BASE_DIR}/hypre-${VERSION}
HYPRE_SRC_DIR=${HYPRE_DIR}/src

# Fetch hypre repository
cd ${BASE_DIR}
rm -rf ${HYPRE_DIR}
git clone https://github.com/hypre-space/hypre.git ${HYPRE_DIR}

# Assign git variables
cd ${HYPRE_DIR}
git checkout ${VERSION}
HYPRE_DEVELOP_STRING=$(git -C ${HYPRE_SRC_DIR} describe --match 'v*' --long --abbrev=9)
HYPRE_DEVELOP_LASTAG=$(git -C ${HYPRE_SRC_DIR} describe --match 'v*' --abbrev=0)
HYPRE_DEVELOP_NUMBER=$(git -C ${HYPRE_SRC_DIR} rev-list --count $HYPRE_DEVELOP_LASTAG..HEAD)
HYPRE_DEVELOP_BRANCH=$(git -C ${HYPRE_SRC_DIR} rev-parse --abbrev-ref HEAD)

# Replace placeholders in the "configure" file
sed -i "s/\$develop_string/$HYPRE_DEVELOP_STRING/g"  ${HYPRE_SRC_DIR}/configure
sed -i "s/\$develop_lasttag/$HYPRE_DEVELOP_LASTAG/g" ${HYPRE_SRC_DIR}/configure
sed -i "s/\$develop_number/$HYPRE_DEVELOP_NUMBER/g"  ${HYPRE_SRC_DIR}/configure
sed -i "s/\$develop_branch/$HYPRE_DEVELOP_BRANCH/g"  ${HYPRE_SRC_DIR}/configure
sed -i "s/\$HYPRE_SRCDIR\/..\/.git/\$HYPRE_SRCDIR/g"   ${HYPRE_SRC_DIR}/configure

# Remove git machinery from configure
sed -i '/^[[:space:]]*develop_lastag=\$/d' ${HYPRE_SRC_DIR}/configure
sed -i '/^[[:space:]]*develop_number=\$/d' ${HYPRE_SRC_DIR}/configure
sed -i '/^[[:space:]]*develop_branch=\$/d' ${HYPRE_SRC_DIR}/configure
sed -i '/^[[:space:]]*develop_string=\$/d' ${HYPRE_SRC_DIR}/configure

# Remove hypre test data
rm -rf ${HYPRE_DIR}/AUTOTEST
rm -rf ${HYPRE_DIR}/src/test/TEST_*

# Remove git folder
rm -rf ${HYPRE_DIR}/.git

# Create tarball
HYPRE_DIR=${BASE_DIR}/hypre-${HYPRE_DEVELOP_STRING}
cd ${BASE_DIR}
mv hypre-${VERSION} ${HYPRE_DIR}
tar czvf hypre-${HYPRE_DEVELOP_STRING}.tar.gz hypre-${HYPRE_DEVELOP_STRING}

# Remove temporary directory
rm -rf ${HYPRE_DIR}
