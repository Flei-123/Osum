#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/svgicons/menushot.sh <outdir> <uiscale> [<apps-dir>] [<mode>] -- start menu + search + bar pictures with the bundle icons
set -uo pipefail
cd "$(dirname "$0")/../.."
OUTD=$1
SCALE=$2
[ -n "${3:-}" ] && export APPS_DIR=$3
MODE=${4:-light}
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat theme"
bash tools/design/eh6.sh "$TMPD/o" res=1280x800 uiscale="$SCALE" accel=kvm mode="$MODE" progs="$PROGS" lang=en tafel=nein \
    pins=explorer,settings,terminal,store,taskmgr \
    tbextra="height=48;align=center;labels=never;hide_missing=1" \
    drehbuch="$(dirname "$0")/menu.txt" > "$TMPD/o.log" 2>&1 < /dev/null
mkdir -p "$OUTD"; cp "$TMPD"/o/*.ppm "$TMPD/o/serial.txt" "$OUTD/" 2>/dev/null
ls "$OUTD"; tail -3 "$TMPD/o.log"
