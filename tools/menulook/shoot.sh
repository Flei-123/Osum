#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?out dir}
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$OUT"
DESIGNBUILD="$TMPD/build" bash tools/design/eh6.sh "$TMPD/o" res=1280x800 accel=kvm progs="$PROGS" drehbuch="$PWD/tools/menulook/dreh.txt" > "$OUT/log.txt" 2>&1
cp "$TMPD"/o/*.ppm "$OUT/" 2>/dev/null
cp "$TMPD/o/serial.txt" "$OUT/serial.txt" 2>/dev/null
ls "$OUT"
