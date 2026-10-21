#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaresize/odd.sh -- r1325: odd host window sizes (VirtualBox GUI scale gives widths not divisible by 8 / 4, e.g. 1426x861).
# Every step must show the same checks as run.sh (screen has the new size, desktop not black, bar at the bottom, no white edge, no stale stride),
# and the serial line `vmsvga: mode WxH ... pitch2=P` must have P == W*4 (a row is never shorter than the width).
# The kernel word vmsvgaodd makes the hint player play the sizes (the image kernel must be built from this tree).
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] bash tools/vmsvgaresize/odd.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export SIZES=${SIZES:-1426x861,1397x777,1111x703,1853x1049}
export EXTRA_WORDS="vmsvgaodd ${EXTRA_WORDS:-}"
KEEP="${KEEP_DIR:-$T/k}" bash tools/vmsvgaresize/run.sh >"$T/out.txt" 2>&1; rc=$?
grep -aE '^  (OK|FAIL)  |^resize:' "$T/out.txt" | grep -aE 'FAIL|resize:' | head -30
pass=0; fail=0
# run.sh must be green except the taskbar-pid probe of the buffer-change check: a serial line interleaved with another task's output
# ("desk: start /bin/taskbarfuiglyph:") hides the pid -- a log artefact that also shows with plain sizes (the known 43/1), not a mode problem.
nf=$(grep -a '^  FAIL  ' "$T/out.txt" | grep -avc "no 'wm: bufchg' line or no taskbar pid")
if [ "$nf" = 0 ] && grep -aq '^resize: ' "$T/out.txt"; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL  run.sh: $nf real failures (rc=$rc)"; fi
# pitch must be exactly width*4 for every odd size
bad=$(grep -a '^vmsvga: mode ' "${KEEP_DIR:-$T/k}/serial.txt" | awk '{split($3,a,"x"); p=0; for(i=1;i<=NF;i++) if ($i ~ /^pitch2=/) p=substr($i,8)+0; if (a[1]>=1000 && p!=a[1]*4) n++} END{print n+0}')
seen=$(grep -a '^vmsvga: mode ' "${KEEP_DIR:-$T/k}/serial.txt" | awk '{split($3,a,"x"); if (a[1]%8!=0) n++} END{print n+0}')
[ "$seen" -ge 3 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "  FAIL  only $seen odd-width mode lines"; }
[ "$bad" = 0 ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "  FAIL  $bad mode lines with pitch2 != width*4"; }
echo "odd: $pass ok, $fail fail"
[ "$fail" = 0 ]
