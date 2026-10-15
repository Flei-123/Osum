#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/i2csim/run.sh -- I2C-HID touchpad path against a SIMULATED DesignWare controller.
#
# QEMU has no DW_apb_i2c, so the register path of kernel/drv/hid/i2chid.fi
# (dw_setup, dw_xfer, reg_read, versuche, poll) never ran. Word `i2csim`
# puts a software model behind the MMIO accessors (controller address 1):
# TAR changes only while disabled, an unknown slave aborts (TX_ABRT), a
# write phase + RESTART read selects the register, reports only flow after
# SET_POWER(on). The device is the precision touchpad of hidtest.
#
# Checks: the decoy slave 0x15 aborts and the probe goes on to 0x2C; HID
# description parsed (vid 0x4f3); power-on + reset sent exactly once; no TAR
# write while enabled; the 8 pad reports come through poll() -> hidin and
# give the SAME events as the direct replay of tools/hid/run.sh section 4
# (+100 px x, 0xb5 y, left click, one wheel notch); empty queue = no event.
# Counter-check `noi2c`: the stage stays silent.
#
# Usage: bash tools/i2csim/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
export FIRNLIB="$PWD/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
OK=0; FAIL=0
eq() { # name expected got
    if [ "$2" = "$3" ]; then OK=$((OK+1)); printf '  ok    %s (%s)\n' "$1" "$3"
    else FAIL=$((FAIL+1)); printf '  FAIL  %s: expected <%s>, got <%s>\n' "$1" "$2" "$3"; fi
}
yes_() { # name rc
    if [ "$2" -eq 0 ]; then OK=$((OK+1)); printf '  ok    %s\n' "$1"
    else FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; fi
}
echo "== 0. build"
if [ -n "${I2CSIM_IMG:-}" ]; then IMG=$I2CSIM_IMG
else IMG="$TMPD/osum.mb"; ./tools/build-kernel.sh "$IMG" > /dev/null || { echo "build failed"; exit 1; }; fi
run() { # name cmdline
    timeout 60 $QEMU_X86 -kernel "$IMG" -m 256 -append "$2" \
        -serial "file:$TMPD/$1.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo $?
}
echo "== 1. simulated controller + touchpad"
RC=$(run sim "i2csim nokbd noring3 nofs")
eq "run ends cleanly (exit 21)" 21 "$RC"
S="$TMPD/sim.txt"
L=$(grep -a '^i2csim: ready=' "$S")
eq "device found and parsed" 1 "$(echo "$L" | sed 's/.*ready=\([0-9]*\).*/\1/')"
eq "decoy slave 0x15 aborted twice (two description registers)" 2 "$(echo "$L" | sed 's/.* aborts=\([0-9]*\).*/\1/')"
eq "SET_POWER sent once" 1 "$(echo "$L" | sed 's/.* poweron=\([0-9]*\).*/\1/')"
eq "RESET sent once" 1 "$(echo "$L" | sed 's/.* resets=\([0-9]*\).*/\1/')"
eq "no TAR write while the controller was enabled" 0 "$(echo "$L" | sed 's/.* tarbad=\([0-9]*\).*/\1/')"
eq "vendor id from the HID description" 0x4f3 "$(echo "$L" | sed 's/.* vid=\(0x[0-9a-f]*\).*/\1/')"
eq "descriptor parse line (pad slot 3)" 1 "$(grep -ac '^hidrep: .*dev=3' "$S" | sed 's/^[1-9][0-9]*$/1/')"
R=$(grep -a '^i2csim: reports=' "$S")
eq "8 reports delivered by poll()" 8 "$(echo "$R" | sed 's/.*reports=\([0-9]*\) .*/\1/')"
eq "no read timeouts" 0 "$(echo "$R" | sed 's/.*timeouts=\([0-9]*\).*/\1/')"
grep -aq '^hidev: maus 0x0 x=0x64 y=0x0 r=0x0' "$S"; yes_ "+300 units x -> 100 px through I2C" $?
grep -aq '^hidev: maus 0x0 x=0x0 y=0xb5 r=0x0' "$S"; yes_ "+150 units y -> 75 px (0xb5)" $?
grep -aq '^hidev: maus 0x1 x=0x0 y=0x0 r=0x0' "$S"; yes_ "pad button = left click" $?
grep -aq '^hidev: maus 0x0 x=0x0 y=0x0 r=0x1' "$S"; yes_ "two fingers -> one wheel notch" $?
eq "exactly 5 mouse events (4 + button release; empty poll adds none)" 5 "$(grep -ac '^hidev: maus' "$S")"
echo "== 2. counter-check noi2c"
RC=$(run off "i2chid noi2c nokbd noring3 nofs")
eq "run ends cleanly" 21 "$RC"
eq "noi2c: stage prints its line" 1 "$(grep -ac 'i2chid: noi2c' "$TMPD/off.txt")"
echo "== 3. without the word nothing is printed"
RC=$(run none "nokbd noring3 nofs")
eq "no i2csim lines" 0 "$(grep -ac '^i2csim:' "$TMPD/none.txt")"
echo; echo "i2csim: $OK ok, $FAIL fail"
[ "$FAIL" -eq 0 ]
