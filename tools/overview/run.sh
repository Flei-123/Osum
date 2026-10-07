#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/overview/run.sh -- THE FILE MANAGER'S OVERVIEW OF ALL DRIVES ("This computer", Justin's order A, 07.10.2026).
#
#   bash tools/overview/run.sh        (start it through /root/jarvis/bin/heavy)
#
# The pane has a row "Overview" in the group "This computer"; it opens a list of every mounted drive: name, the fill as a number AND as
# a bar, the kind, the free room. `explorer computer` starts in that view (no clicking needed to take the picture). The checks read
# what the program REPORTS (rows, crumbs) and what is in the PICTURE (bar pixels), not a layout from memory.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 1. start in the overview =="
bash tools/toolbench/build.sh "$TMPD/o" app=/bin/explorer,computer wait=12 last=100 shot=allein > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
[ -s "$TMPD/o/allein.ppm" ] && ok "the picture was taken" || { bad "no picture: $(tail -3 "$TMPD/o.log" | tr '\n' ' ')"; echo "OVERVIEW: $pass passed, $fail failed"; exit 1; }
N=$(grep -aoE 'explorer: overview [0-9]+' "$S" | tail -1 | grep -oE '[0-9]+$')
[ "${N:-0}" -ge 1 ] && ok "the overview lists $N drive(s)" || bad "no 'explorer: overview N' (n=${N:-?})"
grep -aqE 'explorer: krume n=1 ' "$S" && ok "the crumbs are the one link 'Overview'" || bad "the crumbs are not the overview's one link: $(grep -a 'explorer: krume' "$S" | tail -1)"

echo "== 2. the picture =="
python3 - "$TMPD/o/allein.ppm" "$S" <<'PY' && ok "the Used cell of the first drive has a bar: a track and a filled part" || bad "no bar in the picture"
import re, sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
txt = open(sys.argv[2], "rb").read().decode("latin1")
# the window origin and the list: `explorer: geom` and the table rectangle (id 25 in the reports of this program)
g = re.findall(r"explorer: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)
gx, gy = int(g[-1][0]), int(g[-1][1])
rects = {int(m.group(1)): tuple(int(m.group(k)) for k in (3, 4, 5, 6)) for m in
         re.finditer(r"explorer: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)}
ox, oy = gx + 1, gy + 33
best = None
for rid, (x, y, w, h) in rects.items():
    if w > 300 and h > 200:
        best = (x, y, w, h)
if best is None:
    print("no list rectangle"); sys.exit(1)
x, y, w, h = best
# the first data row is the second row of the list (the header is the first): 32 px each; a bar lies in the lower part of the Used cell
accent = (37, 99, 235)
fill = 0
track = 0
for yy in range(oy + y + 32, oy + y + 32 + 32):
    for xx in range(ox + x, ox + x + w):
        p = im.getpixel((xx, yy))
        if sum(abs(a - b) for a, b in zip(p, accent)) < 40:
            fill += 1
        if abs(p[0] - 203) < 6 and abs(p[1] - 213) < 6 and abs(p[2] - 225) < 6:
            track += 1
print("accent pixels in the first row: %d, track pixels: %d" % (fill, track))
sys.exit(0 if fill > 20 and track > 20 else 1)
PY

mkdir -p docs/shots/overview
[ -s "$TMPD/o/allein.ppm" ] && python3 tools/design/ppm2png.py "$TMPD/o/allein.ppm" docs/shots/overview/overview.png > /dev/null 2>&1

echo
echo "OVERVIEW: $pass passed, $fail failed"
[ "$fail" = 0 ]
