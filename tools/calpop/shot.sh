#!/usr/bin/env bash
# tools/calpop/shot.sh <outdir> -- boot the desktop, drive the calendar popup (dreh.txt), keep serial + pictures in <outdir>
set -uo pipefail
cd "$(dirname "$0")/../.."
OUTD=$1
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
printf 'Ada\t111\tada@x.org\nBob\t222\t\nCy\t333\t\nDee\t444\t\n' > "$TMPD/contacts"
export EH_ETC_EXTRA="/etc/contacts=$TMPD/contacts@0644"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
O="$TMPD/o"
bash tools/design/eh6.sh "$O" res=1280x800 accel=kvm ton=ja mode=light progs="$PROGS" lang=de tafel=nein \
    tbextra="height=48;align=center;labels=never;clock_seconds=0;clock_date=1;clock_weekday=0;clock_lines=2;clock_year4=1;tray_language=1;tray_chevron=1;tray_group=1;hide_missing=1" \
    drehbuch="$(dirname "$0")/scene.txt" > "$TMPD/o.log" 2>&1 < /dev/null
mkdir -p "$OUTD"; cp "$O"/*.ppm "$O/serial.txt" "$OUTD/" 2>/dev/null
ls "$OUTD"; tail -3 "$TMPD/o.log"
