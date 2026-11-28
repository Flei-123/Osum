#!/usr/bin/env bash
set -uo pipefail
WD=${1:?workdir}
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/linuxcompat
ROOT=$WD/root
SHARE=$ROOT/usr/share/linuxcompat
BUILD_DIR=$ROOT/tmp/lcbuild
BUILD_PKGS="go rust gcc musl-dev openjdk21"
mkdir -p "$SHARE/java" "$BUILD_DIR"
cp "$SRC/gotest.go" "$SRC/rusttest.rs" "$SRC/Compat.java" "$SRC/gdbhello.c" "$BUILD_DIR/" || exit 1
cp "$SRC/pycompat.py" "$SRC/nodecompat.js" "$SHARE/" || exit 1
chroot "$ROOT" /sbin/apk add --no-cache --virtual .lcbuild $BUILD_PKGS > "$WD/apk-build.log" 2>&1 || { tail -n 3 "$WD/apk-build.log"; exit 1; }
BUILD_CMD='cd /tmp/lcbuild && export TMPDIR=/tmp HOME=/tmp/lcbuild GOCACHE=/tmp/lcbuild/gocache CGO_ENABLED=0 && go build -o /usr/share/linuxcompat/gotest gotest.go && rustc -O --edition 2021 -o /usr/share/linuxcompat/rusttest rusttest.rs && javac -d /usr/share/linuxcompat/java Compat.java && gcc -g -O0 -o /usr/share/linuxcompat/gdbhello gdbhello.c'
bwrap --bind "$ROOT" / --proc /proc --dev /dev --unshare-pid --die-with-parent /bin/sh -c "$BUILD_CMD" > "$WD/build-tests.log" 2>&1 || { tail -n 8 "$WD/build-tests.log"; exit 1; }
chroot "$ROOT" /sbin/apk del .lcbuild >> "$WD/apk-build.log" 2>&1
rm -rf "$BUILD_DIR" "$ROOT/root/.cache" "$ROOT/root/go" "$ROOT/root/.cargo"
