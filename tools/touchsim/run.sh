#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/touchsim/run.sh -- W-TOUCH3 gate: two simulated DesignWare controllers (A: touchpad, B: touch
# screen + pen + a hanging device) behind i2chid. Word `touchsim`. Counter-check `i2cold` (old behaviour:
# first controller, first device) must give NO touch events. UNTESTED when written -- run via heavy.
# Usage: bash tools/touchsim/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
export FIRNLIB="$PWD/lib"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
OK=0; FAIL=0
eq() { if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  ok    %s (%s)\n' "$1" "$3"; else FAIL=$((FAIL+1)); printf '  FAIL  %s: expected <%s>, got <%s>\n' "$1" "$2" "$3"; fi; }
if [ -n "${TOUCHSIM_IMG:-}" ]; then IMG=$TOUCHSIM_IMG; else IMG="$TMPD/osum.mb"; ./tools/build-kernel.sh "$IMG" > /dev/null || { echo "build failed"; exit 1; }; fi
run() { timeout 60 $QEMU_X86 -kernel "$IMG" -m 256 -append "$2" -serial "file:$TMPD/$1.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1; echo $?; }
echo "== 1. two controllers"
RC=$(run new "touchsim nokbd noring3 nofs"); eq "run ends cleanly" 21 "$RC"
S="$TMPD/new.txt"
L=$(grep -a '^touchsim: ctrls=' "$S")
eq "2 controllers" 2 "$(echo "$L" | sed 's/.*ctrls=\([0-9]*\).*/\1/')"
eq "3 devices (pad, screen, pen); hanging device not registered" 3 "$(echo "$L" | sed 's/.* devs=\([0-9]*\).*/\1/')"
T=$(echo "$L" | sed 's/.* timeouts=\([0-9]*\).*/\1/'); [ "$T" -ge 1 ] && [ "$T" -le 6 ]; eq "hang -> 1..6 timeouts" 0 $?
eq "touch tap events (down, tap)" 1 "$(grep -ac '^hidev: touch 0x1 ' "$S" | sed 's/^[1-9][0-9]*$/1/')"
eq "tap code 5 once" 1 "$(grep -ac '^hidev: touch 0x5 ' "$S")"
eq "long press code 6 once" 1 "$(grep -ac '^hidev: touch 0x6 ' "$S")"
eq "drag end code 4 once" 1 "$(grep -ac '^hidev: touch 0x4 ' "$S")"
eq "scroll notches (code 7) >= 4" 1 "$([ "$(grep -ac '^hidev: touch 0x7 ' "$S")" -ge 4 ] && echo 1 || echo 0)"
eq "pen events (code 8) >= 3" 1 "$([ "$(grep -ac '^hidev: touch 0x8 ' "$S")" -ge 3 ] && echo 1 || echo 0)"
echo "== 2. counter-check i2cold (first controller / first device only)"
RC=$(run old "touchsim i2cold nokbd noring3 nofs"); eq "run ends cleanly" 21 "$RC"
eq "i2cold: no touch events" 0 "$(grep -ac '^hidev: touch' "$TMPD/old.txt")"
echo; echo "touchsim: $OK ok, $FAIL fail"; [ "$FAIL" -eq 0 ]
