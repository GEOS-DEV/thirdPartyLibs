#!/bin/sh
set -x
set -e

# Installing latest `CMake` version available
PREFIX=/usr/local
VERSION=1.11.1

curl -fsSL https://github.com/ninja-build/ninja/releases/download/v$VERSION/ninja-linux.zip | \
zcat >$PREFIX/bin/ninja

chmod +x $PREFIX/bin/ninja