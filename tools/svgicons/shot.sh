#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/svgicons/shot.sh <outdir> <uiscale> [<apps-dir>] -- boot the desktop with pinned bundles, keep serial + bar picture
set -uo pipefail
cd "$(dirname "$0")/../.."
OUTD=$1
SCALE=$2
[ -n "${3:-}" ] && export APPS_DIR=$3
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
O="$TMPD/o"
bash tools/design/eh6.sh "$O" res=1280x800 uiscale="$SCALE" accel=kvm ton=ja mode=light progs="$PROGS" lang=en tafel=nein \
    pins=explorer,settings,terminal \
    tbextra="height=48;align=center;labels=never;hide_missing=1" \
    drehbuch="$(dirname "$0")/scene.txt" > "$TMPD/o.log" 2>&1 < /dev/null
mkdir -p "$OUTD"; cp "$O"/*.ppm "$O/serial.txt" "$OUTD/" 2>/dev/null
ls "$OUTD"; tail -3 "$TMPD/o.log"
