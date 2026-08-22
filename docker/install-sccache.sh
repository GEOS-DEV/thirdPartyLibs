#!/bin/sh
set -xe

# Install `sccache` binaries to speed up the build of `geos`
# 0.8.2 adds HIP compiler support while retaining the v0.7 cache format.
VERSION=${1-0.8.2}
PREFIX=${2-/opt/sccache}

mkdir -p $PREFIX/bin
curl -fsSL https://github.com/mozilla/sccache/releases/download/v$VERSION/sccache-v$VERSION-x86_64-unknown-linux-musl.tar.gz | \
tar --directory=$PREFIX/bin --strip-components=1 -xzf -
