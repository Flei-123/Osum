#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ps2hid/run.sh -- PS/2-ONLY pointer gate (W-I, 17.10.2026): wheel + right click with NO USB controller (VirtualBox hands the guest a
# PS/2 mouse only; tools/usbhid cannot see that path).
#
#   /root/jarvis/bin/heavy bash tools/ps2hid/run.sh
#
# Two boots of the stick's machine with `usb=nein` (eh6.sh):
#   1. tools/term/scroll.txt: wheel over the terminal moves the scrollback (judged by tools/term/scroll.py)
#   2. tools/ps2hid/explorer.txt: right click on the file list opens the context menu (`explorer: menurect`)
# and the serial must show the PS/2 path: `mouse: id=` line and no USB HID mouse.
# Counter-proof (PS2_COUNTER=1): the same boots through usb=ja must NOT report a PS/2-only mouse -- proves the witness line distinguishes.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
# PS2_BUILD=<dir> reuses one kernel build across repeated runs (tools/ps2hid/repeat.sh); default: fresh build per run
export DESIGNBUILD="${PS2_BUILD:-$TMPD/build}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
USB=${PS2_USB:-nein}
bash tools/design/eh6.sh "$TMPD/s" accel=kvm usb="$USB" drehbuch=tools/term/scroll.txt > "$TMPD/s.log" 2>&1
bash tools/design/eh6.sh "$TMPD/e" accel=kvm usb="$USB" res=1280x800 drehbuch=tools/ps2hid/explorer.txt > "$TMPD/e.log" 2>&1
SS="$TMPD/s/serial.txt"; SE="$TMPD/e/serial.txt"
if [ -n "${PS2_KEEP:-}" ]; then
    mkdir -p "$PS2_KEEP"; cp "$SS" "$PS2_KEEP/s.txt" 2>/dev/null; cp "$SE" "$PS2_KEEP/e.txt" 2>/dev/null
fi
[ -s "$SS" ] && [ -s "$SE" ] || { bad "no serial output"; tail -5 "$TMPD/s.log" "$TMPD/e.log"; echo "PS2HID: $pass passed, $fail failed"; exit 1; }
if [ "$USB" = nein ]; then
    grep -qaE 'usb devices=0|usb: skipped' "$SE" && ok "no USB devices on the machine" || bad "USB devices present (not a PS/2-only boot)"
    grep -qaE 'mouse: id=[0-9]' "$SE" && ok "PS/2 mouse reported (mouse: id=)" || bad "no PS/2 mouse line"
else
    grep -qaE 'usb devices=0|usb: skipped' "$SE" && bad "counter-proof: usb=ja still shows no USB devices" || ok "counter-proof: usb=ja has USB devices"
fi
out=$(python3 tools/term/scroll.py "$SS"); rc=$?
echo "$out" | grep -E 'FAIL|OK' | head -12
[ "$rc" = 0 ] && ok "wheel scrolls the terminal over PS/2 (scroll.py)" || bad "wheel does not scroll the terminal over PS/2"
n=$(grep -ac 'explorer: menurect' "$SE")
[ "$n" -ge 1 ] && ok "right click opened the context menu ($n menurect)" || bad "no context menu after right click"
echo "PS2HID: $pass passed, $fail failed"
[ "$fail" = 0 ]
