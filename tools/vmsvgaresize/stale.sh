#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaresize/stale.sh -- 800x600 on a host whose BYTES_PER_LINE register stays STALE after a mode set (VirtualBox, measured with
# z10c: 800x600 kept 4096 instead of 3200 -> every row shifted, "line garbage"). Kernel word `vmsvgastale` emulates the stale register
# and makes the hint player cycle 1280x720, 800x600, 1024x768, 800x600; the existing run.sh checks (screen size, desktop not black, bar at
# the bottom, bar NOT repeated by a stale stride) must hold for every step.
# Case 1: current set_mode -> must be green. Case 2 (COUNTER-PROOF): word `vmsvgaold` (the old set_mode that trusts a register value
# >= width*4) -> must show the stale stride (dup share / size checks FAIL).
# Usage: [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] bash tools/vmsvgaresize/stale.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
if [ -z "${IMG:-}" ] && [ -z "${STICK_DIR:-}" ]; then
    mkdir -p "$T/build"
    PARTTAB=mbr bash tools/usbimg/build.sh "$T/build" >"$T/build.log" 2>&1 || { echo "stick build failed"; tail -15 "$T/build.log"; exit 1; }
    IMG=$T/build/orientos-usb.img
fi
export IMG STICK_DIR
export SIZES=1280x720,800x600,1024x768,800x600
pass=0; fail=0
# r1197: VirtualBox kept the OLD stride after a live WIDTH/HEIGHT change (cbLine 0x1000 for 1920 wide: small shifted rectangle / black window).
# set_mode now writes ENABLE=0 + PITCHLOCK=width*4 first; the serial line `vmsvga: mode WxH ... lock=L` must show L == W*4 on every hint step.
lockcheck() { # <serial> -> "<lines with lock>/<bad lines>"
    awk '/^vmsvga: mode /{split($3,a,"x"); l=0; for(i=1;i<=NF;i++) if ($i ~ /^lock=/) {l=substr($i,6)+0}; if (l>0) {n++; if (l!=a[1]*4) b++}} END{print n+0 "/" b+0}' "$1"
}
echo "== current set_mode (vmsvgastale)"
KEEP="$T/k1" PROBE_EXPECT="full full small full" EXTRA_WORDS="vmsvgastale" bash tools/vmsvgaresize/run.sh >"$T/new.txt" 2>&1; rc=$?
grep -aE '^  (OK|FAIL)  .*(800x600|login|probe|2 s after)' "$T/new.txt" | head -20
if [ "$rc" = 0 ]; then pass=$((pass+1)); echo "  OK    stale register: all resize checks green incl. 800x600"; else fail=$((fail+1)); echo "  FAIL  stale register: run.sh rc=$rc"; tail -5 "$T/new.txt"; fi
lc=$(lockcheck "$T/k1/serial.txt")
if [ "${lc%/*}" -ge 3 ] && [ "${lc#*/}" = 0 ]; then pass=$((pass+1)); echo "  OK    pitch lock = width*4 on every live mode change ($lc)"; else fail=$((fail+1)); echo "  FAIL  pitch lock lines/bad: $lc (need >= 3 / 0)"; fi
echo "== counter-proof (vmsvgaold + vmsvgastale)"
KEEP="$T/k2" EXTRA_WORDS="vmsvgastale vmsvgaold" bash tools/vmsvgaresize/run.sh >"$T/old.txt" 2>&1; rc2=$?
grep -aE '^  FAIL  .*800x600' "$T/old.txt" | head -6
nf=$(grep -ac '^  FAIL  .*800x600' "$T/old.txt")
if [ "$rc2" != 0 ] && [ "$nf" -ge 1 ]; then pass=$((pass+1)); echo "  OK    old set_mode goes red on 800x600 ($nf failing 800x600 checks)"; else fail=$((fail+1)); echo "  FAIL  counter-proof did not go red (rc=$rc2, 800x600 fails=$nf)"; fi
lc2=$(lockcheck "$T/k2/serial.txt")
if [ "${lc2%/*}" = 0 ]; then pass=$((pass+1)); echo "  OK    old set_mode writes no pitch lock (counter-proof, $lc2)"; else fail=$((fail+1)); echo "  FAIL  counter-proof still locks: $lc2"; fi
echo "stale: $pass ok, $fail fail"
[ "$fail" = 0 ]
