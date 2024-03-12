#!/bin/sh
set -xe

# Installing latest `CMake` version available
PREFIX=/usr/local
VERSION=3.28.3

curl -s https://cmake.org/files/v${VERSION%.[0-9]*}/cmake-$VERSION-linux-x86_64.tar.gz | \
tar --directory=$PREFIX --strip-components=1 -xzf -
