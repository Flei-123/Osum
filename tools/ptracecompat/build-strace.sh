#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
SRC=${1:?usage: build-strace.sh <strace.tar.xz> <outdir>}
OUT=$(realpath -m "${2:?outdir}")
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
K=$W/khdr
mkdir -p "$K" "$OUT"
for d in linux asm-generic mtd; do ln -sfn /usr/include/$d "$K/$d"; done
ln -sfn /usr/include/x86_64-linux-gnu/asm "$K/asm"
mkdir -p "$W/b" && cd "$W/b"
tar xf "$SRC"
cd strace-*
./configure --host=x86_64-linux-gnu --enable-mpers=no --disable-gcc-Werror --without-libunwind --without-libdw --without-libiberty \
  CC="musl-gcc -isystem $K" CFLAGS="-O2 -fPIE -D_GNU_SOURCE" LDFLAGS="-pie" > "$W/configure.log" 2>&1 || { tail -30 "$W/configure.log"; exit 1; }
make -j4 > "$W/make.log" 2>&1 || { tail -40 "$W/make.log"; exit 1; }
cp src/strace "$OUT/strace"
