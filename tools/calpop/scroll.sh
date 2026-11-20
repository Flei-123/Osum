#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
KEEP=${1:-}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
export DESIGNBUILD="$D/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq notify"
bash tools/design/eh6.sh "$D/o" res=1280x800 accel=kvm ton=ja mode=dark progs="$PROGS" lang=de tafel=nein \
    tbextra="height=48;align=center;labels=never;clock_seconds=0;clock_date=1;clock_weekday=0;clock_lines=2;clock_year4=1;tray_language=1;tray_chevron=1;tray_group=1;hide_missing=1" \
    drehbuch="$PWD/tools/calpop/scroll.txt" > "$D/o.log" 2>&1 < /dev/null
[ -n "$KEEP" ] && { mkdir -p "$KEEP"; cp "$D"/o/*.ppm "$D"/o/serial.txt "$KEEP/" 2>/dev/null; }
python3 -I tools/calpop/scrollcheck.py "$D/o"
