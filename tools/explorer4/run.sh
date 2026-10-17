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
# Counter-proof: run it on the tree before W4b (git worktree of the old main + this directory): every claim is red.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
RES=${RES:-1280x800}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaE "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- missing: $2"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "EXPLORER4: skipped, no qemu"; exit 0; }
python3 -c "import PIL" 2>/dev/null || { echo "EXPLORER4: skipped, no Pillow"; exit 0; }

cat > "$OUT/dreh.txt" <<'DREH'
warteauf explorer: ready || 240
warte 8
foto 10-base
# --- 4. column resize first (the table is at its widest)
ziehnach fkante0 40,0
warte 3
foto 11-resized
# --- 2. sort menu: Size (row 1), Type (row 3), Reversed (row 4)
klickauf frect41
warteauf explorer: menurect || 60
warte 2
foto 12-sortmenu
klickauf emenue1
warte 3
klickauf frect41
warteauf explorer: menurect || 60
warte 2
klickauf emenue3
warte 3
klickauf frect41
warteauf explorer: menurect || 60
warte 2
klickauf emenue4
warte 3
foto 13-sorted
# --- 3. Alt+P
klickauf ftab
warte 2
taste alt-p
warte 4
foto 14-preview
taste alt-p
warte 3
foto 15-nopreview
DREH
bash tools/design/capture.sh "$OUT/lauf" res="$RES" uitrace=yes lang=de \
    extra='nostart wigapp=/bin/explorer' drehbuch="$OUT/dreh.txt" > "$OUT/lauf.log" 2>&1
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

echo "== 3. Alt+P preview pane =="
hat "$S" 'explorer: preview on=1' "Alt+P switches the preview pane on"
hat "$S" 'explorer: preview on=0' "Alt+P again switches it off"

echo "== 4. column resize by header drag =="
read -r a b <<<"$(python3 - "$S" <<'PY'
import re, sys
t = open(sys.argv[1], 'rb').read().decode('latin1')
sp = re.findall(r'explorer: spalten (\d+) (\d+) (\d+) (\d+)', t)
print(sp[0][1] if sp else 0, sp[-1][1] if sp else 0)
PY
)"
cr=$(grep -aoE 'explorer: colresize a=[0-9]+' "$S" | tail -1 | grep -oE '[0-9]+$')
hat "$S" 'explorer: colresize a=[0-9]+' "the drag reports the new column widths"
[ "${cr:-0}" -gt 0 ] 2>/dev/null && ok "column 0 has a user width (a=$cr)" || bad "no user width for column 0"
d=$((b - a))
[ "$d" -ge 24 ] && [ "$d" -le 56 ] && ok "column 1 moved right by $d px for a 40 px drag" || bad "column 1 moved by $d px (first $a, last $b), expected 24..56"

echo "== 5. catalog =="
for k in explorer.cmd explorer.menu.new explorer.menu.sort explorer.menu.show explorer.preview.none explorer.preview.title; do
    grep -qE "^$k =" locale/de/messages && grep -qE "^$k =" locale/en/messages \
        && ok "catalog key $k in de and en" || bad "catalog key $k missing"
done

echo "EXPLORER4: $pass passed, $fail failed"
[ "$fail" = 0 ]
