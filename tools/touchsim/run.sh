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
echo "== 1b. /proc/inputdevs text (render, printed by the sim)"
eq "inputdevs head: 2 ctrls, 3 devs, 3 hid" 1 "$(grep -ac '^inputdevs: i2c_ctrls=2 i2c_devs=3 i2c_hung=0 .* hid_devs=3$' "$S")"
eq "inputdevs: one line per controller" 2 "$(grep -ac '^inputdevs: ctrl[0-9] bdf=' "$S")"
eq "inputdevs: touch screen line (ctrl 1, adr 0x10, kind 16)" 1 "$(grep -ac '^inputdevs: dev1 ctrl=1 adr=0x10 kind=16 slot=4 ' "$S")"
eq "inputdevs: pen line (kind 32)" 1 "$(grep -ac '^inputdevs: dev2 ctrl=1 adr=0x11 kind=32 ' "$S")"
eq "inputdevs: hid slot lines" 3 "$(grep -ac '^inputdevs: hid[0-9] kind=' "$S")"
echo "== 2. counter-check i2cold (first controller / first device only)"
RC=$(run old "touchsim i2cold nokbd noring3 nofs"); eq "run ends cleanly" 21 "$RC"
eq "i2cold: no touch events" 0 "$(grep -ac '^hidev: touch' "$TMPD/old.txt")"
eq "i2cold: inputdevs shows no device (old path stops at the decoy)" 1 "$(grep -ac '^inputdevs: i2c_ctrls=2 i2c_devs=0 ' "$TMPD/old.txt")"
echo "== 3. AML path (SSDT tools/touchsim/asl/hidi2c.aml: PNP0C50 devices, _CRS, controller _ADR, _DSM; decoy 0x15 is no PNP0C50)"
[ -f tools/touchsim/asl/hidi2c.aml ] || ( cd tools/touchsim/asl && iasl hidi2c.asl > /dev/null 2>&1 )
runt() { timeout 60 $QEMU_X86 -kernel "$IMG" -m 256 -append "$2" -acpitable file=tools/touchsim/asl/hidi2c.aml -serial "file:$TMPD/$1.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1; echo $?; }
RC=$(runt aml "touchsim nokbd noring3 nofs"); eq "run ends cleanly" 21 "$RC"
A="$TMPD/aml.txt"
eq "3 candidates from AML" 1 "$(grep -ac '^i2chid: aml n=3$' "$A")"
eq "candidate pad: ctrl 0, adr 0x2c, _DSM reg 0x1 (UUID compare in AML worked)" 1 "$(grep -ac '^i2chid: aml cand=0 ctrl=0 adr=0x2c hreg=0x1$' "$A")"
eq "candidate touch screen: ctrl 1, adr 0x10, _DSM reg 0x20" 1 "$(grep -ac '^i2chid: aml cand=1 ctrl=1 adr=0x10 hreg=0x20$' "$A")"
eq "candidate pen: no _DSM -> reg none" 1 "$(grep -ac '^i2chid: aml cand=2 ctrl=1 adr=0x11 hreg=0xffffffff$' "$A")"
L=$(grep -a '^touchsim: ctrls=' "$A")
eq "AML: 3 devices" 3 "$(echo "$L" | sed 's/.* devs=\([0-9]*\).*/\1/')"
eq "AML: no timeout (hanging 0x40 never touched)" 0 "$(echo "$L" | sed 's/.* timeouts=\([0-9]*\).*/\1/')"
eq "AML: no abort (decoy 0x15 never touched)" 0 "$(echo "$L" | sed 's/.* aborts=\([0-9]*\).*/\1/')"
eq "AML: tap code 5 once" 1 "$(grep -ac '^hidev: touch 0x5 ' "$A")"
eq "AML: pen events >= 3" 1 "$([ "$(grep -ac '^hidev: touch 0x8 ' "$A")" -ge 3 ] && echo 1 || echo 0)"
eq "AML: inputdevs says via=aml for all 3" 3 "$(grep -ac '^inputdevs: dev[0-9] .* via=aml ' "$A")"
eq "AML: inputdevs head i2c_aml=1" 1 "$(grep -ac '^inputdevs: .* i2c_aml=1 ' "$A")"
echo "== 4. counter-checks: word i2cnoaml, and no table"
RC=$(runt noaml "touchsim i2cnoaml nokbd noring3 nofs"); eq "i2cnoaml: run ends cleanly" 21 "$RC"
eq "i2cnoaml: no AML candidates" 1 "$(grep -ac '^i2chid: aml n=0$' "$TMPD/noaml.txt")"
eq "i2cnoaml: byte search still finds 3 devices" 3 "$(grep -a '^touchsim: ctrls=' "$TMPD/noaml.txt" | sed 's/.* devs=\([0-9]*\).*/\1/')"
eq "i2cnoaml: the hanging address was tried (timeout)" 1 "$(grep -a '^touchsim: ctrls=' "$TMPD/noaml.txt" | sed 's/.* timeouts=\([0-9]*\).*/\1/')"
eq "i2cnoaml: inputdevs says via=search" 3 "$(grep -ac '^inputdevs: dev[0-9] .* via=search ' "$TMPD/noaml.txt")"
RC=$(run notab "touchsim nokbd noring3 nofs"); eq "no table: run ends cleanly" 21 "$RC"
eq "no table: no AML candidates, byte search finds 3 devices" 1 "$(grep -ac '^i2chid: aml n=0$' "$TMPD/notab.txt")"
echo; echo "touchsim: $OK ok, $FAIL fail"; [ "$FAIL" -eq 0 ]
