#!/bin/sh
set -xe

# Installing latest `ninja` version available
VERSION=${1-1.11.1}
PREFIX=${2-/usr/local}

curl -fsSL https://github.com/ninja-build/ninja/releases/download/v$VERSION/ninja-linux.zip | \
zcat >$PREFIX/bin/ninja

chmod +x $PREFIX/bin/ninja
