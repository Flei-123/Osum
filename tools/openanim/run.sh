#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/openanim/run.sh -- open animations: start menu, context menu, program window.
#
#   bash tools/openanim/run.sh
#
# Machine of the stick (tools/design/eh6.sh, 1280x800, KVM), word `animtrace`. Three boots of the same tree:
#   slow   theme motion=2400 (15x): picture series per animation (Win key, right click, program start) + `wm: animf` trace
#   off    the same script with the word `noanim`: the control. No trace lines, the end pictures are the reference
#   fast   shipping speed, no pictures: duration and frame gaps from the trace
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=${OPENANIM_OUT:-$(mktemp -d)}
mkdir -p "$TMPD"
[ -n "${OPENANIM_OUT:-}" ] || trap 'rm -rf "$TMPD"' EXIT
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
export DESIGNBUILD="$TMPD/build"
mkdir -p "$TMPD/slow" "$TMPD/off" "$TMPD/fast"
common=(res=1280x800 accel=kvm moreprogs=term progs="$PROGS" tafel=nein)
bash tools/design/eh6.sh "$TMPD/prep" "${common[@]}" nurbau=ja > "$TMPD/prep.log" 2>&1
tail -3 "$TMPD/prep.log"
bash tools/design/eh6.sh "$TMPD/slow/o" "${common[@]}" extra="animtrace" themeextra="motion=2400" drehbuch="$ROOT/tools/openanim/slow.txt" > "$TMPD/slow/run.log" 2>&1 &
bash tools/design/eh6.sh "$TMPD/off/o" "${common[@]}" extra="animtrace noanim" themeextra="motion=2400" drehbuch="$ROOT/tools/openanim/slow.txt" > "$TMPD/off/run.log" 2>&1 &
bash tools/design/eh6.sh "$TMPD/fast/o" "${common[@]}" extra="animtrace" drehbuch="$ROOT/tools/openanim/fast.txt" > "$TMPD/fast/run.log" 2>&1 &
wait
python3 -I tools/openanim/check.py "$TMPD/slow/o" "$TMPD/off/o" "$TMPD/fast/o" | tee "$TMPD/result.txt"
! grep -q '^  FAIL' "$TMPD/result.txt"
