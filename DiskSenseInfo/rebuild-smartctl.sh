#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/vendor
 tar -xzf Resources/smartmontools-7.5-source.tar.gz -C build/vendor
cd build/vendor/smartmontools-7.5
./configure --without-libcap-ng --without-libsystemd --without-selinux \
 CXXFLAGS='-O2 -mmacosx-version-min=13.0 -arch arm64 -arch x86_64' \
 CFLAGS='-O2 -mmacosx-version-min=13.0 -arch arm64 -arch x86_64' \
 LDFLAGS='-arch arm64 -arch x86_64'
make -j4 smartctl
cp smartctl ../../../Resources/smartctl
cp drivedb.h ../../../Resources/drivedb.h
