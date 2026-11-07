#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
OUTD=$1
MODE=${2:-new}
CLIP=$3
UISCALE=${4:-1}
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify vplay"
SCENE="$(dirname "$0")/scene.txt"
if [ "$MODE" = nosync ]; then sed 's/^tippe vplay -t /tippe vplay -t -n /' "$SCENE" > "$TMPD/scene.txt"; SCENE="$TMPD/scene.txt"; fi
O="$TMPD/o"
bash tools/design/eh6.sh "$O" res=1280x800 accel=kvm ton=ja mode=light progs="$PROGS" lang=en tafel=nein uiscale="$UISCALE" xfile="/etc/clip.mov=$CLIP" drehbuch="$SCENE" > "$TMPD/o.log" 2>&1 < /dev/null
mkdir -p "$OUTD"; cp "$O"/*.ppm "$O/serial.txt" "$O/fahren.log" "$OUTD/" 2>/dev/null
ls "$OUTD" | tr '\n' ' '; tail -3 "$TMPD/o.log"
