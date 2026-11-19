#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
export DESIGNBUILD="$TMPD/build"
mkdir -p "$TMPD/new" "$TMPD/off"
common=(res=1280x800 accel=kvm moreprogs=term progs="$PROGS" tafel=nein pins=settings extra="animtrace" drehbuch="$ROOT/tools/taskmotion/script.txt")
bash tools/design/eh6.sh "$TMPD/prep" "${common[@]}" nurbau=ja > "$TMPD/prep.log" 2>&1
bash tools/design/eh6.sh "$TMPD/new/o" "${common[@]}" > "$TMPD/new/run.log" 2>&1 &
bash tools/design/eh6.sh "$TMPD/off/o" "${common[@]}" themeextra="motion=0" > "$TMPD/off/run.log" 2>&1 &
wait
if [ -n "${TASKMOTION_OUT:-}" ]; then
    mkdir -p "$TASKMOTION_OUT"
    cp "$TMPD"/new/o/*.ppm "$TMPD/new/o/serial.txt" "$TASKMOTION_OUT/" 2>/dev/null
    cp "$TMPD/off/o/serial.txt" "$TASKMOTION_OUT/off-serial.txt" 2>/dev/null
fi
echo "== new tree =="
python3 -I tools/taskmotion/check.py "$TMPD/new/o" "$TMPD/off/o" | tee "$TMPD/new.txt"
echo "== control: motion=0 =="
python3 -I tools/taskmotion/check.py "$TMPD/off/o" off | tee "$TMPD/off.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt"); o1=$(grep -c '^  OK' "$TMPD/new.txt")
f2=$(grep -c '^  FAIL' "$TMPD/off.txt")
echo "TASKMOTION: $o1 passed, $f1 failed, control $f2 failed"
[ "$f1" -eq 0 ] && [ "$f2" -eq 0 ]
