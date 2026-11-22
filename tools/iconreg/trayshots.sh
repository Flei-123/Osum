#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?output dir}
SCALE=${2:-1}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
python3 -I tools/appreg/build.py "$PWD" "$TMPD/reg" > "$TMPD/reg.log" 2>&1 || { cat "$TMPD/reg.log"; exit 1; }
printf 'terminal|0|Terminal\ncalc|0|Calculator\nnosuchapp|0|Unknown program\n' > "$TMPD/tray.items"
cat > "$TMPD/script.txt" <<'EOT'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-bar
klickauf chevron
warteauf 'traypop: open' || 25
warte 3
foto 01-overflow
klickauf chevron
warte 3
klickauf start
warte 6
klickauf start_File Explorer
warte 12
taste ctrl-l
warte 2
taste ctrl-a
tippe /bin
taste ret
warte 6
foto 02-explorer-bin
EOT
EH_APPREG_DIR="$TMPD/reg" EH_MKFS_EXTRA="/run/ /run/tray.items=$TMPD/tray.items@0644" bash tools/design/eh6.sh "$TMPD/run" res=1920x1080 uiscale="$SCALE" accel=kvm mode=light progs="$PROGS" \
    tbextra="tray_chevron=1;tray_apps=terminal:1" drehbuch="$TMPD/script.txt" > "$TMPD/run.log" 2>&1 < /dev/null
mkdir -p "$OUT"
cp "$TMPD"/run/*.ppm "$TMPD"/run/serial.txt "$OUT/" 2>/dev/null
tail -3 "$TMPD/run.log"
