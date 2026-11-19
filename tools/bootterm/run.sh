#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bootterm/run.sh -- boot word `nobootterm`: NO terminal window on the fresh desktop.
#   /root/jarvis/bin/heavy bash tools/bootterm/run.sh
# Two boots of the stick machine (tools/design/eh6.sh): A with `nobootterm`, B without (counter-proof). The rectangle where the kernel
# opens the console window (24,40 560x380 at scale 1) must look like bare wallpaper in A and like a window in B.
# A creates no console window at all, so program output cannot land in a visible terminal.
set -uo pipefail
cd "$(dirname "$0")/../.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
printf 'warte 25\nfoto shot\nwarte 2\n' > "$T/s.txt"
printf 'warte 25\nklickauf pinterminal\nwarte 6\nfoto pin\nwarte 2\n' > "$T/p.txt"
run() { bash tools/design/eh6.sh "$T/$1" accel=kvm res=1280x800 "extra=$2" ${4:-} drehbuch="$T/${3:-s.txt}" > "$T/$1.log" 2>&1; }
run a "nobootterm"
run b ""
run c "nobootterm" p.txt "pins=terminal,explorer moreprogs=term tafel=nein"
for n in a b; do [ -s "$T/$n/shot.ppm" ] && ok "$n: screenshot exists" || bad "$n: no screenshot ($(tail -2 "$T/$n.log" | tr '\n' ' '))"; done
grep -aq 'wm: console sh' "$T/a/serial.txt" && ok "A: the shell still runs without a window" || bad "A: no console shell line"
grep -aq 'wm: no console window' "$T/a/serial.txt" && ok "A: no console window created" || bad "A: no 'no console window' line"
grep -aq 'wm: term win=' "$T/a/serial.txt" && bad "A: a console window exists" || ok "A: no console window"
grep -aq 'wm: no console window' "$T/b/serial.txt" && bad "B: window skipped without the word (counter-proof broken)" || ok "B (counter-proof): without the word the window is created"
grep -aq 'wm: term win=' "$T/b/serial.txt" && ok "B (counter-proof): console window exists" || bad "B: no console window"
grep -aq 'taskbar: pin starte /apps/terminal.osp' "$T/c/serial.txt" && grep -aq 'taskbar: pin terminal .* running=1' "$T/c/serial.txt" && ok "C: the Terminal pin opens a fresh terminal window" || bad "C: pin click opened no terminal window"
[ -s "$T/c/pin.ppm" ] && ok "C: pin screenshot exists" || bad "C: no pin screenshot"
tm() { bash tools/toolbench/build.sh "$T/$1" desk=yes "app=/bin/taskmgr,$2takt,200" wait=12 last=300 > "$T/$1.log" 2>&1; }
tm d ""
tm e "report,"
SPAM='taskmgr: reset'
grep -aq 'desk: start /bin/taskmgr' "$T/d/serial.txt" && ok "D: taskmgr started" || bad "D: taskmgr did not start"
[ "$(grep -ac "$SPAM" "$T/d/serial.txt")" = 0 ] && ok "D: no 'taskmgr: reset' trace without report" || bad "D: taskmgr reset spam"
[ "$(grep -ac "$SPAM" "$T/e/serial.txt")" -gt 0 ] && ok "E (counter-proof): report mode still prints the reset marker" || bad "E: report mode prints no reset marker"
echo "== $pass ok, $fail fail =="
[ "$fail" = 0 ]
