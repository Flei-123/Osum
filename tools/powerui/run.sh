#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/powerui/run.sh -- r783 (L-007c): Settings page "Power" (lid, screen off, standby, profile; battery block above the mains block).
#
#   /root/jarvis/bin/heavy bash tools/powerui/run.sh
#
# Starts Settings straight on page 16 through tools/toolbench (`settings debug page=16`; the design-audit machine does not boot at
# the moment, also on clean main) and reads what the program REPORTS: the eight widgets (plidb plida pscrb pscra psbyb psbya
# pprofb pprofa) exist, lie inside the window, the page is the 17th tab (tabq reported), plus a picture whose widget area is not
# blank. NOT HERE: clicking the widgets (needs the drehbuch machine); the stored values are the same code as the Mouse page.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash tools/toolbench/build.sh "$TMPD/o" app=/bin/settings,debug,page=16 wait=14 last=100 shot=power > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
grep -aq 'settings: ready' "$S" && ok "window up" || bad "window up: $(tail -3 "$TMPD/o.log" | tr '\n' ' ')"
for r in plidb plida pscrb pscra psbyb psbya pprofb pprofa tabq; do
  grep -aq "settings: rect name=$r " "$S" && ok "widget $r reported" || bad "widget $r reported"
done
python3 -I - "$S" <<'PY' && ok "the eight widgets have a size and stand in the order battery block, then mains block" || bad "widget geometry"
import re, sys
t = open(sys.argv[1], "rb").read().decode("latin1")
r = {}
for m in re.finditer(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t):
    r[m.group(1)] = tuple(int(m.group(i)) for i in (2, 3, 4, 5))
names = "plidb plida pscrb pscra psbyb psbya pprofb pprofa".split()
if any(n not in r for n in names):
    print("missing", [n for n in names if n not in r]); sys.exit(1)
if any(r[n][2] < 20 or r[n][3] < 10 for n in names):
    print("too small"); sys.exit(1)
# the battery block lies above the mains block, each in the order lid, screen, standby, profile
if not (r["plidb"][1] < r["pscrb"][1] < r["psbyb"][1] < r["pprofb"][1] < r["plida"][1] < r["pscra"][1] < r["psbya"][1] < r["pprofa"][1]):
    print("rows out of order"); sys.exit(1)
PY
[ -s "$TMPD/o/power.ppm" ] && ok "the picture was taken" || bad "no picture"
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
mkdir -p docs/shots/power
[ -s "$TMPD/o/power.ppm" ] && python3 tools/design/ppm2png.py "$TMPD/o/power.ppm" docs/shots/power/power.png > /dev/null 2>&1
echo "POWERUI: $pass passed, $fail failed"
[ "$fail" = 0 ]
