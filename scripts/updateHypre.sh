#!/bin/bash

# Input argument: hypre branch
VERSION=${1:-"master"}

# Local variables
GEOSTPL_DIR=$(dirname $(dirname $(realpath $0)))
TPL_MIRROR_DIR=${GEOSTPL_DIR}/tplMirror

# Find git hash
HYPRE_GIT_HASH=$(git ls-remote https://github.com/hypre-space/hypre.git refs/heads/${VERSION} | cut -f1)

# Create tarball and check sha256
cd ${GEOSTPL_DIR}
wget https://github.com/hypre-space/hypre/archive/${HYPRE_GIT_HASH}.tar.gz
HYPRE_SHA256=$(sha256sum ${HYPRE_GIT_HASH}.tar.gz | cut -d' ' -f1)
rm -rf ${HYPRE_GIT_HASH}.tar.gz
echo -e "sha256sum: ${HYPRE_SHA256}"

# Update CMakeLists
echo -e "Updating CMakeLists..."
sed -i "s|set( HYPRE_URL \"https://github.com/hypre-space/hypre/archive/.*\.tar\.gz\" )|set( HYPRE_URL \"https://github.com/hypre-space/hypre/archive/${HYPRE_GIT_HASH}.tar.gz\" )|" CMakeLists.txt
sed -i "s|set( HYPRE_URL_HASH \".*\" )|set( HYPRE_URL_HASH \"${HYPRE_SHA256}\" )|" CMakeLists.txt

# Update YAML files with new hypre git hash
find scripts docker -name "*.yaml" -type f | while read -r file; do
    sed -i -E "/hypre:/,/require:/s/@git\.[a-f0-9]{40}/@git.${HYPRE_GIT_HASH}/" "$file"
done
echo -e "Updated YAML files with new hypre git hash: ${HYPRE_GIT_HASH}"

# Stage changes
git add -u scripts docker CMakeLists.txt
git commit -m "Update hypre to ${HYPRE_GIT_HASH}"
