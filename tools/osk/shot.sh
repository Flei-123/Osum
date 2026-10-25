#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUTD=$1
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify osk osktest"
SCENE="$(dirname "$0")/scene.txt"
if [ "${2:-}" = badscan ]; then sed 's/^tippe osktest$/tippe osktest badscan/' "$SCENE" > "$TMPD/scene.txt"; SCENE="$TMPD/scene.txt"; fi
O="$TMPD/o"
bash tools/design/eh6.sh "$O" res=1280x800 accel=kvm ton=ja mode=light progs="$PROGS" lang=en tafel=nein drehbuch="$SCENE" > "$TMPD/o.log" 2>&1 < /dev/null
mkdir -p "$OUTD"; cp "$O"/*.ppm "$O/serial.txt" "$O/fahren.log" "$OUTD/" 2>/dev/null
ls "$OUTD" | tr '\n' ' '; tail -3 "$TMPD/o.log"
