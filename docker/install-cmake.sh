#!/bin/sh
set -xe

# Installing latest `CMake` version available
VERSION=${1-3.28.6}
PREFIX=${2-/usr/local}

curl -S https://cmake.org/files/v${VERSION%.[0-9]*}/cmake-$VERSION-linux-x86_64.tar.gz | \
tar --directory=$PREFIX --strip-components=1 -xzf -
