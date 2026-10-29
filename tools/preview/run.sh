#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/preview/run.sh -- gate for the host preview (TOOLKIT-PLAN T3 / r1326):
# axpng.py renders a real a11y.tree dump (tests/preview/scenedemo.tree, taken
# from tools/a11y/scene.sh) to a PNG, watch.sh compiles + renders. No VM.
#
#   bash tools/preview/run.sh        # ~25 s (two firnc compiles of scenedemo)
#
# Counter-proofs: a moved button, a removed node, a wrong window title and a
# broken source must each turn the matching check red.
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
FX=tests/preview/scenedemo.tree
AX="python3 -I tools/preview/axpng.py"

# pixel(png, win_x, win_y, x, y) -> r,g,b of the point of a node coordinate (scale 1, pad 8)
px() { python3 -I -c '
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
x, y = int(sys.argv[2]) + 8, int(sys.argv[3]) + 8
print("%d,%d,%d" % im.getpixel((x, y)))' "$@"; }
# dark pixels (text) inside a node rectangle
ink() { python3 -I -c '
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
x, y, w, h = [int(v) for v in sys.argv[2:6]]
n = 0
for j in range(y + 8, y + 8 + h):
    for i in range(x + 8, x + 8 + w):
        if im.getpixel((i, j)) < 100: n += 1
print(n)' "$@"; }

echo "== 1. parse the real dump =="
n=$($AX $FX --list | wc -l)
[ "$n" = 5 ] && ok "5 window dumps found in the fixture" || bad "window dumps: $n"
$AX $FX --window Szenenbaum --json > "$T/n.json" 2>/dev/null
python3 -I - "$T/n.json" <<'EOF' && ok "tree of Szenenbaum: roles, rect, flags, act, name" || bad "tree content wrong"
import json, sys
ns = json.load(open(sys.argv[1]))
by = {n["name"]: n for n in ns}
assert ns[0]["role"] == "window" and (ns[0]["w"], ns[0]["h"]) == (320, 240)
b = by["Klick!"]
assert (b["role"], b["x"], b["y"], b["w"], b["h"], b["act"]) == ("button", 8, 208, 304, 32, "scene.click"), b
assert "selected" in by["Eins"]["flags"] and by["Eins"]["role"] == "tab"
assert by["Passwort"]["role"] == "password" and "protected" in by["Passwort"]["flags"]
EOF
$AX $FX --window Mehrfenster --json | grep -q '"Zurück!"' && bad "window 700 shows nodes of window 701" || ok "windows are kept apart (Mehrfenster has no Zurück!)"
$AX $FX --window Zweit --json | grep -q '"Zurück!"' && ok "second window has its own tree" || bad "Zweit tree missing"

echo "== 2. render + pixel check =="
$AX $FX --window Szenenbaum -o "$T/a.png" > /dev/null && ok "PNG written" || bad "render failed"
[ "$(px "$T/a.png" 160 220)" = "253,253,253" ] && ok "button face where the tree puts the button (160,220)" || bad "button face missing: $(px "$T/a.png" 160 220)"
[ "$(px "$T/a.png" 250 140)" = "255,255,255" ] && ok "entry field fill where the tree puts the entry" || bad "entry field missing"
[ "$(ink "$T/a.png" 8 120 304 36)" -gt 20 ] && ok "entry shows its text (dark pixels > 20)" || bad "entry text missing"
[ "$(px "$T/a.png" 30 79)" = "0,95,184" ] && ok "selected tab Eins carries the accent bar" || bad "accent bar missing: $(px "$T/a.png" 30 79)"
[ "$(px "$T/a.png" 90 79)" != "0,95,184" ] && ok "unselected tab Zwei has none" || bad "Zwei has the accent bar"
$AX $FX --window Szenenbaum --dark -o "$T/d.png" > /dev/null && [ "$(px "$T/d.png" 160 220)" = "55,55,55" ] && ok "dark theme switches the colours" || bad "dark theme"

echo "== 3. counter-proofs =="
sed 's/^node.9=button win600 8,208/node.9=button win600 108,208/' $FX > "$T/moved.tree"
$AX "$T/moved.tree" --window Szenenbaum -o "$T/m.png" > /dev/null
[ "$(px "$T/m.png" 20 220)" != "253,253,253" ] && ok "button moved in the dump -> the old spot is empty (the picture follows the tree)" || bad "moved button not followed"
grep -v '"Klick!"' $FX > "$T/nobtn.tree"
$AX "$T/nobtn.tree" --window Szenenbaum -o "$T/nb.png" > /dev/null
[ "$(px "$T/nb.png" 160 220)" != "253,253,253" ] && ok "button removed from the dump -> no button face" || bad "removed button still drawn"
$AX $FX --window NichtDa -o "$T/x.png" > /dev/null 2>&1 && bad "unknown window accepted" || ok "unknown window title -> exit 1, no PNG"
[ ! -e "$T/x.png" ] && ok "... and no file written" || bad "file written for unknown window"
cmp -s "$T/a.png" "$T/m.png" && bad "moved dump renders the same PNG" || ok "moved dump renders a different PNG"

echo "== 4. watch.sh: compile + render =="
bash tools/preview/watch.sh scenedemo --once --dump $FX --window Szenenbaum --out "$T/w.png" > "$T/w.txt" 2>&1
grep -q '^BUILD ok   scenedemo' "$T/w.txt" && ok "scenedemo compiles ($(grep -o '[0-9.]* s' "$T/w.txt" | head -1))" || { bad "scenedemo does not build"; head -8 "$T/w.txt"; }
[ -s "$T/w.png" ] && ok "watch --once left a preview PNG" || bad "no preview from watch.sh"
mkdir -p "$T/usrc"; cp kernel/user/* "$T/usrc"/ 2>/dev/null
printf '\nfn broken_on_purpose( {\n' >> "$T/usrc/scenedemo.fi"
USRC="$T/usrc" bash tools/preview/watch.sh scenedemo --once > "$T/w2.txt" 2>&1; rc=$?
[ $rc = 1 ] && grep -q '^BUILD FAIL' "$T/w2.txt" && ok "broken source -> BUILD FAIL, exit 1 (counter-proof)" || bad "broken source not caught (rc=$rc)"

echo "PREVIEW: $pass passed, $fail failed"
[ "$fail" = 0 ]
