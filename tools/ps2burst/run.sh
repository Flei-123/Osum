#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ps2burst/run.sh -- PS/2 mouse burst gate (VirtualBox freeze r670): thousands of relative packets back to back (no USB), the desktop must stay alive.
#
#   /root/jarvis/bin/heavy bash tools/ps2burst/run.sh [outdir]
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="${PS2_BUILD:-$TMPD/build}"
OUT=${1:-$TMPD/o}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash tools/design/eh6.sh "$OUT" accel=kvm usb=nein extra="phases wmshell wmdauer" drehbuch="$(pwd)/tools/ps2burst/burst.txt" > "$TMPD/b.log" 2>&1
S="$OUT/serial.txt"
[ -s "$S" ] || { bad "no serial output"; tail -n 5 "$TMPD/b.log"; echo "PS2BURST: $pass passed, $fail failed"; exit 1; }
grep -qaE 'mouse: id=[0-9]' "$S" && ok "PS/2 mouse path" || bad "no PS/2 mouse line"
n=$(grep -ac 'wm: frame' "$S")
[ "$n" -ge 7 ] && ok "desktop alive after every flood ($n frame reports)" || bad "desktop stopped reporting ($n of 7 frame reports)"
grep -qaiE 'panic|stall:|soft lockup|#DF|#GP' "$S" && bad "panic/stall line in serial" || ok "no panic/stall line"
echo "PS2BURST: $pass passed, $fail failed"
[ "$fail" = 0 ]
