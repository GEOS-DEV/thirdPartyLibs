#!/bin/sh
set -e
set -x

sudo yum -y install bison flex
sudo yum -y install clang-7.0.0-1-1.tce.ch6_2.x86_64.rpm

rm /home/geosx/clang-7.0.0-public-1-1.tce.ch6_2.x86_64.rpm
rm /home/geosx/clang-7.0.0-1-1.tce.ch6_2.x86_64.rpm
