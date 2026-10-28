#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
WD=${1:?workdir}; VER=${PIXBUF_VER:-2.44.7}; HERE=$(cd "$(dirname "$0")" && pwd)
B=$WD/pixbuf; FX=$WD/fx-root; L=usr/lib/gdk-pixbuf-2.0/2.10.0; SO=libgdk_pixbuf-2.0.so.0.4400.7
mkdir -p "$B/root"
[ -d "$B/root/bin" ] || tar -xzf /root/fremdquellen/alpine-minirootfs-3.24.2-x86_64.tar.gz -C "$B/root"
cp /etc/resolv.conf "$B/root/etc/resolv.conf"
if [ ! -d "$B/root/src" ]; then
    [ -f "$B/gdk-pixbuf-$VER.tar.xz" ] || curl -fsS -m 300 -o "$B/gdk-pixbuf-$VER.tar.xz" "https://download.gnome.org/sources/gdk-pixbuf/${VER%.*}/gdk-pixbuf-$VER.tar.xz"
    mkdir -p "$B/root/src" && tar -xJf "$B/gdk-pixbuf-$VER.tar.xz" -C "$B/root/src" --strip-components=1
fi
cp "$HERE/pixbuf-chroot-build.sh" "$B/root/build.sh"
mkdir -p "$B/root/dev"
mount --bind /dev "$B/root/dev"
trap 'umount "$B/root/dev" 2>/dev/null || true' EXIT
chroot "$B/root" /bin/sh /build.sh > "$B/build.log" 2>&1 || { tail -5 "$B/build.log"; exit 1; }
rm -f "$FX/$L/loaders/libpixbufloader-png.so" "$FX/$L/loaders/libpixbufloader-jpeg.so"
cp "$B/root/out.so" "$FX/usr/lib/$SO"
echo "PIXBUF: builtin png+jpeg libgdk_pixbuf installed into $FX/usr/lib"
