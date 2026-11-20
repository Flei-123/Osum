#!/usr/bin/env bash
set -uo pipefail
WD=${1:?workdir}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$WD/root/usr/share/wine"
x86_64-w64-mingw32-gcc -O1 -o "$WD/root/usr/share/wine/hello.exe" "$HERE/wine-hello.c" || exit 1
APP_PKGS=${APP_PKGS:-"wine"} APP_TREES="/usr/share/wine /opt/pfx" APP_HOOK="$HERE/mkprefix.sh" bash "$HERE/prep-apps.sh" "$WD"
