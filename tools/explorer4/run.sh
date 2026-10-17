#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/explorer4/run.sh -- EXPLORER COMMAND BAR, SORT MENU, PREVIEW PANE, COLUMN RESIZE (W4b/W4c, 17.10.2026).
#
#   /root/jarvis/bin/heavy bash tools/explorer4/run.sh
#
# One machine, one script (tools/design/drive.py), the explorer under /etc/uitrace:
#  1. command bar in a row of its own, WORDS next to the icons: `explorer: cmdbar mode=N hid=N` with mode >= 1
#  2. sort menu opened by a click on the Sort button; the rows drive `explorer: sort spalte= rev=` (size 1, type 4, reversed)
#  3. Alt+P toggles the preview pane: `explorer: preview on=1`, again on=0
#  4. a drag on the right edge of the header cell of column 0 widens it: `explorer: colresize a=` and the
#     text start of column 1 (`explorer: spalten`) moves right by about the drag
#  5. catalog keys (de + en) of the new words
#  3c. X5 picture preview: a PNG (red | blue) and a binary PPM (green | yellow) in /users/justin; the pane shows them
#      (`explorer: preview img state=1 w= h=`, plus the pure colours in the screen dump; the text-only dump has none)
#  4b. X5 column widths per folder: a drag, into the config folder (defaults: `explorer: colmem hit=0`), back
#      (`hit=1`, same widths as after the drag)
#  4c. X5 resize cursor: the header edge hand over reports shape 3 (source check) and the cursor shape on the wire
#  3b. preview content: row 1 of /users/justin (brief.txt) -> `explorer: preview txt n=21`
# Counter-proof: run it on the tree before W4b (git worktree of the old main + this directory): every claim is red.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
# KEEP=<dir>: keep the run's output (serial log, dumps) there instead of deleting it
if [ -n "${KEEP:-}" ]; then OUT=$KEEP; mkdir -p "$OUT"; else OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
RES=${RES:-1280x800}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaE "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- missing: $2"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "EXPLORER4: skipped, no qemu"; exit 0; }
python3 -c "import PIL" 2>/dev/null || { echo "EXPLORER4: skipped, no Pillow"; exit 0; }

mkdir -p "$OUT/pics"
python3 - "$OUT/pics" <<'PY'
import sys
from PIL import Image
d = sys.argv[1]
im = Image.new("RGB", (64, 48))
for y in range(48):
    for x in range(64):
        im.putpixel((x, y), (255, 0, 0) if x < 32 else (0, 0, 255))
im.save(d + "/zz-pic.png")
with open(d + "/zz-pic.ppm", "wb") as f:
    f.write(b"P6\n# test\n32 32\n255\n")
    for y in range(32):
        for x in range(32):
            f.write(bytes((0, 255, 0) if x < 16 else (255, 255, 0)))
PY
export HOMEFILES="$OUT/pics"

cat > "$OUT/dreh.txt" <<'DREH'
warteauf explorer: ready || 240
warte 8
foto 10-base
# --- 4. column resize first (the table is at its widest)
ziehnach fkante0 40,0
warte 3
foto 11-resized
# --- 4b. per-folder widths: into the config folder (row 0) and back up with Backspace
marke explorer: colmem hit=0
doppelauf ftabzeile0
warteneu explorer: colmem hit=0 || 60
warte 3
foto 14-other-folder
marke explorer: colmem hit=1
taste backspace
warteneu explorer: colmem hit=1 || 60
warte 4
foto 15-back
# --- right click first (before the picture steps): the context menu of the file list
marke explorer: menurect
rklickauf ftab
warteneu explorer: menurect || 60
warte 2
foto 16-context
taste esc
warte 3
# --- 3. preview pane with the first bytes of a text file: row 1 is brief.txt (row 0 is the folder config)
klickauf ftabzeile1
warte 2
taste alt-p
warte 4
foto 17-preview-text
# --- 3c. picture previews: row 4 = zz-pic.png, row 5 = zz-pic.ppm
klickauf ftabzeile4
warteauf explorer: preview img state=1 w=64 h=48 || 60
warte 3
foto 18-preview-png
klickauf ftabzeile5
warteauf explorer: preview img state=1 w=32 h=32 || 60
warte 3
foto 19-preview-ppm
taste alt-p
warte 3
# --- 2. sort menu: Size (row 1), Type (row 3), Reversed (row 4)
marke explorer: menurect
klickauf frect41
warteneu explorer: menurect || 60
warte 2
foto 12-sortmenu
klickauf emenue1
warte 3
marke explorer: menurect
klickauf frect41
warteneu explorer: menurect || 60
warte 2
klickauf emenue3
warte 3
marke explorer: menurect
klickauf frect41
warteneu explorer: menurect || 60
warte 2
klickauf emenue4
warte 3
foto 13-sorted
DREH
bash tools/design/capture.sh "$OUT/lauf" res="$RES" uitrace=yes lang=de \
    extra='nostart wigapp=/bin/explorer,/users/justin' drehbuch="$OUT/dreh.txt" > "$OUT/lauf.log" 2>&1
S="$OUT/lauf/serial.txt"
if [ ! -s "$S" ]; then echo "FAILED: no serial output"; tail -20 "$OUT/lauf.log"; exit 1; fi
hat "$S" 'explorer: ready' "the explorer came up"

echo "== 1. command bar with words =="
m=$(grep -aoE 'explorer: cmdbar mode=[0-9]+' "$S" | tail -1 | grep -oE '[0-9]+$')
[ "${m:-0}" -ge 1 ] 2>/dev/null && ok "words next to the icons (mode=$m)" || bad "no word mode (mode=${m:-none})"
hat "$S" 'explorer: rect id=41 kind=2 ' "the Sort button is reported (id=41)"

echo "== 2. sort menu =="
n=$(grep -ac 'explorer: menurect' "$S")
[ "$n" -ge 3 ] && ok "the Sort button opened a menu three times ($n menurect lines)" || bad "only $n menurect lines"
hat "$S" 'explorer: sort spalte=1 rev=0' "By size -> sort spalte=1"
hat "$S" 'explorer: sort spalte=4 rev=0' "By type -> sort spalte=4"
hat "$S" 'explorer: sort spalte=4 rev=1' "Reversed -> rev=1"

echo "== 3. Alt+P preview pane, text content =="
hat "$S" 'explorer: preview on=1' "Alt+P switches the preview pane on"
hat "$S" 'explorer: preview on=0' "Alt+P again switches it off"
hat "$S" 'explorer: preview txt n=21' "the preview reads the 21 bytes of brief.txt (\"Ein Brief an Justin.\")"

echo "== 3c. picture preview =="
hat "$S" 'explorer: preview img state=1 w=64 h=48' "the PNG (64x48) decodes into the preview buffer"
hat "$S" 'explorer: preview img state=1 w=32 h=32' "the binary PPM (32x32) decodes into the preview buffer"
python3 - "$OUT/lauf" <<'PY' && ok "the dumps show the picture colours (PNG red+blue, PPM green+yellow), the text-only dump does not" || bad "picture colours missing in the preview dumps"
import sys
from PIL import Image
d = sys.argv[1]
def count(name, rgb):
    im = Image.open("%s/%s.ppm" % (d, name)).convert("RGB")
    w, h = im.size
    # the preview card is the right-hand strip of the window: look at the right 40 % of the picture
    px = im.crop((w * 6 // 10, 0, w, h)).getdata()
    return sum(1 for p in px if p == rgb)
base = {c: count("17-preview-text", c) for c in [(255,0,0),(0,0,255),(0,255,0),(255,255,0)]}
r = count("18-preview-png", (255,0,0)) - base[(255,0,0)]
b = count("18-preview-png", (0,0,255)) - base[(0,0,255)]
g = count("19-preview-ppm", (0,255,0)) - base[(0,255,0)]
y = count("19-preview-ppm", (255,255,0)) - base[(255,255,0)]
print("  red %d blue %d green %d yellow %d (above the text-only dump)" % (r, b, g, y))
sys.exit(0 if min(r, b, g, y) >= 300 else 1)
PY

echo "== 3b. context menu =="
n=$(grep -ac 'explorer: menurect' "$S")
[ "$n" -ge 4 ] && ok "the right click opened a fourth menu ($n menurect lines)" || bad "right click: only $n menurect lines"
wh=$(grep -aoE 'explorer: menurect wx=[0-9]+ wy=[0-9]+ wh=[0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
[ "${wh:-0}" -ge 100 ] 2>/dev/null && ok "the context menu has ${wh} px of rows" || bad "context menu height ${wh:-none}"

echo "== 4. column resize by header drag =="
# before the drag: `explorer: rect id=26 kind=6 x=` (table) and `explorer: spalten x0 x1 ..` (x1 - 10 = right edge of column 0)
w0=$(python3 - "$S" <<'PY'
import re, sys
t = open(sys.argv[1], 'rb').read().decode('latin1')
r = re.findall(r'explorer: rect id=26 kind=6 x=(\d+) ', t)
sp = re.findall(r'explorer: spalten (\d+) (\d+) (\d+) (\d+)', t)
print(int(sp[0][1]) - 10 - int(r[0]) if sp and r else 0)
PY
)
cr=$(grep -aoE 'explorer: colresize a=[0-9]+' "$S" | tail -1 | grep -oE '[0-9]+$')
hat "$S" 'explorer: colresize a=[0-9]+' "the drag reports the new column widths"
d=$(( ${cr:-0} - ${w0:-0} ))
[ "${w0:-0}" -gt 0 ] && [ "$d" -ge 24 ] && [ "$d" -le 56 ] \
    && ok "column 0 grew from $w0 to $cr px for a 40 px drag (+$d)" || bad "column 0: before ${w0:-?}, after ${cr:-?} (+$d), expected +24..56"

echo "== 4b. column widths per folder =="
hat "$S" 'explorer: colmem hit=1' "back in the folder: the stored widths were found (hit=1)"
python3 - "$S" <<'PY' && ok "after the way there and back the columns are as wide as after the drag" || bad "column widths differ after leaving and re-entering the folder"
import re, sys
t = open(sys.argv[1], 'rb').read().decode('latin1')
i = t.index('explorer: colresize')
after = re.findall(r'explorer: colw a=(\d+) b=(\d+) c=(\d+) d=(\d+)', t[:i])[-1:]
j = t.rindex('explorer: colmem hit=1')
back = re.findall(r'explorer: colw a=(\d+) b=(\d+) c=(\d+) d=(\d+)', t[j:])
print("  after drag", after[0] if after else None, "back", back[0] if back else None)
sys.exit(0 if after and back and after[0] == back[0] else 1)
PY

echo "== 4c. resize cursor (source) =="
grep -q 'fn ct_edge_at' kernel/user/fuiscene.fi && grep -q 'shp = 3' kernel/user/fuiscene.fi \
    && ok "fuiscene.scene_cursor answers shape 3 over a header edge and during a drag" || bad "no resize cursor in fuiscene"

echo "== 5. catalog =="
for k in explorer.cmd explorer.menu.new explorer.menu.sort explorer.menu.show explorer.preview.none explorer.preview.title; do
    grep -qE "^$k =" locale/de/messages && grep -qE "^$k =" locale/en/messages \
        && ok "catalog key $k in de and en" || bad "catalog key $k missing"
done

echo "== 6. file type symbols (source): every kind has its own symbol + tint =="
python3 - <<'PY' && ok "9 kinds, 9 different (symbol, tint) pairs in icon_for" || bad "icon_for: kinds share a symbol+tint pair or a kind is missing"
import re, sys
t = open("kernel/user/expmodell.fi", encoding="latin1").read()
b = t[t.index("fn icon_for("):]
b = b[:b.index("\n}\n")]
pairs = re.findall(r"icon_tint\(wlib\.icon_id\(icons\.(\w+)\), (\d+)\)", b)
sys.exit(0 if len(pairs) == 9 and len(set(pairs)) == 9 else 1)
PY

echo "EXPLORER4: $pass passed, $fail failed"
[ "$fail" = 0 ]
