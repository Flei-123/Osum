#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
WD=${1:?workdir}
HERE=$(cd "$(dirname "$0")" && pwd)
PKGS=${APP_PKGS:-$(tr "\n" " " < "$HERE/apps-packages.txt")}
mkdir -p "$WD/root" "$WD/run"
if [ ! -x "$WD/root/sbin/apk" ]; then
    tar -xzf /root/fremdquellen/alpine-minirootfs-3.24.2-x86_64.tar.gz -C "$WD/root" || exit 1
fi
cp /etc/resolv.conf "$WD/root/etc/resolv.conf"
timeout 900 chroot "$WD/root" /sbin/apk add --no-cache $PKGS > "$WD/apk.log" 2>&1 || { tail -3 "$WD/apk.log"; exit 1; }
[ -z "${APP_HOOK:-}" ] || bash "$APP_HOOK" "$WD" || exit 1
python3 -I "$HERE/mkroot.py" "$WD/root" "$WD/run/spec.txt" --base \
    --tree /usr/lib --tree /usr/libexec --tree /usr/share/terminfo --tree /usr/share/vim --tree /usr/share/misc \
    --tree /usr/share/mime --tree /usr/share/icu --tree /usr/share/fonts --tree /usr/share/X11 --tree /usr/share/git-core \
    --tree /usr/share/perl5 --tree /usr/share/cmake --tree /usr/share/ImageMagick-7 --tree /usr/share/lua --tree /usr/share/screen --tree /usr/share/nginx --tree /usr/share/zoneinfo --tree /usr/share/foot --tree /usr/include --tree /etc/ssl $(for t in ${APP_TREES:-}; do printf -- '--tree %s ' "$t"; done) \
    --skip /usr/lib/libc.a
