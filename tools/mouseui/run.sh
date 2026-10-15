#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/mouseui/run.sh -- r804: Settings page "Mouse" incl. the touchpad gestures toggle (mges).
#
#   /root/jarvis/bin/heavy bash tools/mouseui/run.sh
#
# Starts Settings on page 15 through tools/toolbench and reads what the program REPORTS: the widgets mspeed maccel mnat mges
# exist, have a size and stand in this order, plus a non-empty picture and no crash lines.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash tools/toolbench/build.sh "$TMPD/o" app=/bin/settings,debug,page=15 wait=14 last=100 shot=mouse > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up: $(tail -3 "$TMPD/o.log" | tr '\n' ' ')"
for r in mspeed maccel mnat mges; do
  grep -aq "settings: rect name=$r " "$S" && ok "widget $r reported" || bad "widget $r reported"
done
python3 -I - "$S" <<'PY' && ok "the four widgets have a size and stand in order" || bad "widget geometry"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
r = {}
for m in re.finditer(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t):
    r[m.group(1)] = tuple(int(m.group(i)) for i in (2, 3, 4, 5))
names = "mspeed maccel mnat mges".split()
if any(n not in r for n in names):
    print("missing", [n for n in names if n not in r]); sys.exit(1)
if any(r[n][2] < 20 or r[n][3] < 10 for n in names):
    print("too small"); sys.exit(1)
# the battery block lies above the mains block, each in the order lid, screen, standby, profile
if not (r["mspeed"][1] < r["maccel"][1] < r["mnat"][1] < r["mges"][1]):
    print("rows out of order"); sys.exit(1)
PY
[ -s "$TMPD/o/mouse.ppm" ] && ok "the picture was taken" || bad "no picture"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
mkdir -p docs/shots/mouse
[ -s "$TMPD/o/mouse.ppm" ] && python3 tools/design/ppm2png.py "$TMPD/o/mouse.ppm" docs/shots/mouse/mouse.png > /dev/null 2>&1
echo "MOUSEUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
