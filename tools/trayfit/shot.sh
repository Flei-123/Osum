#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/trayfit/shot.sh <outdir> <res> <uiscale> <lang> <extra> -- the tray corner as pictures + serial
#   lang = de|en, extra = more taskbar.conf keys joined by ';' (e.g. "clock_12h=1;clock_weekday=1").
set -uo pipefail
cd "$(dirname "$0")/../.."
OUTD=$1; RES=$2; SC=$3; LANGV=${4:-de}; EXTRA=${5:-}
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
printf 'backup|7|Backup is running\nchat|8|Chat: 2 unread\nmic|1|0\n' > "$TMPD/tray.items"
O="$TMPD/o"
TB="height=48;align=center;labels=never;clock_seconds=0;clock_date=1;clock_weekday=0;clock_lines=2;clock_year4=1;tray_language=1;tray_chevron=1;tray_group=1;hide_missing=1;tray_demo=101;tray_demochg=0"
[ -n "$EXTRA" ] && TB="$TB;$EXTRA"
EH_MKFS_EXTRA="/etc/tray.items=$TMPD/tray.items@0644" bash tools/design/eh6.sh "$O" res=$RES uiscale=$SC accel=kvm mode=light progs="$PROGS" lang=$LANGV tafel=nein \
    tbextra="$TB" drehbuch="$(dirname "$0")/dreh.txt" > "$TMPD/o.log" 2>&1 < /dev/null
mkdir -p "$OUTD"; cp "$O"/*.ppm "$O/serial.txt" "$OUTD/" 2>/dev/null
ls "$OUTD"; tail -n 3 "$TMPD/o.log"
