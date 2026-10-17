#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bootterm/run.sh -- boot word `nobootterm`: NO terminal window on the fresh desktop.
#   /root/jarvis/bin/heavy bash tools/bootterm/run.sh
# Two boots of the stick machine (tools/design/eh6.sh): A with `nobootterm`, B without (counter-proof). The rectangle where the kernel
# opens the console window (24,40 560x380 at scale 1) must look like bare wallpaper in A and like a window in B.
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
printf 'warte 25\nfoto shot\nwarte 2\n' > "$T/s.txt"
run() { bash tools/design/eh6.sh "$T/$1" accel=kvm res=1280x800 "extra=$2" drehbuch="$T/s.txt" > "$T/$1.log" 2>&1; }
run a "nobootterm"
run b ""
for n in a b; do [ -s "$T/$n/shot.ppm" ] && ok "$n: screenshot exists" || bad "$n: no screenshot ($(tail -2 "$T/$n.log" | tr '\n' ' '))"; done
grep -aq 'wm: console sh' "$T/a/serial.txt" && ok "A: the shell still runs behind the hidden window" || bad "A: no console shell line"

grep -aq 'wm: bootterm hidden win=' "$T/a/serial.txt" && ok "A: the console window was created hidden" || bad "A: no 'bootterm hidden' line"
grep -aq 'wm: bootterm hidden' "$T/b/serial.txt" && bad "B: hidden without the word (counter-proof broken)" || ok "B (counter-proof): without the word the window is NOT hidden"
grep -aq 'wm: term win=' "$T/a/serial.txt" && ok "A: the console window exists (hidden, not missing)" || bad "A: no console window at all"
echo "== $pass ok, $fail fail =="
[ "$fail" = 0 ]
