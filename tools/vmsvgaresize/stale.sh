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
echo "== current set_mode (vmsvgastale)"
EXTRA_WORDS="vmsvgastale" bash tools/vmsvgaresize/run.sh >"$T/new.txt" 2>&1; rc=$?
grep -aE '^  (OK|FAIL)  .*(800x600|login)' "$T/new.txt" | head -20
if [ "$rc" = 0 ]; then pass=$((pass+1)); echo "  OK    stale register: all resize checks green incl. 800x600"; else fail=$((fail+1)); echo "  FAIL  stale register: run.sh rc=$rc"; tail -5 "$T/new.txt"; fi
echo "== counter-proof (vmsvgaold + vmsvgastale)"
EXTRA_WORDS="vmsvgastale vmsvgaold" bash tools/vmsvgaresize/run.sh >"$T/old.txt" 2>&1; rc2=$?
grep -aE '^  FAIL  .*800x600' "$T/old.txt" | head -6
nf=$(grep -ac '^  FAIL  .*800x600' "$T/old.txt")
if [ "$rc2" != 0 ] && [ "$nf" -ge 1 ]; then pass=$((pass+1)); echo "  OK    old set_mode goes red on 800x600 ($nf failing 800x600 checks)"; else fail=$((fail+1)); echo "  FAIL  counter-proof did not go red (rc=$rc2, 800x600 fails=$nf)"; fi
echo "stale: $pass ok, $fail fail"
[ "$fail" = 0 ]
