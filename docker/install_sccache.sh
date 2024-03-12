#!/bin/sh
set -e

# Install `sccache` binaries to speed up the build of `geos`
PREFIX=/opt/sccache
VERSION=0.7.7

mkdir -p $PREFIX/bin
curl -fsSL https://github.com/mozilla/sccache/releases/download/v$VERSION/sccache-v$VERSION-x86_64-unknown-linux-musl.tar.gz | \
tar --directory=$PREFIX/bin --strip-components=1 -xzf -
