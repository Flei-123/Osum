#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/pdfbar/run.sh [--old] -- THE PDF VIEWER BAR (r972, 17.10.2026): one Edge-like toolbar in the window.
#
#   bash tools/pdfbar/run.sh          the gate (QEMU, the image's own build of /bin/pdfview)
#   bash tools/pdfbar/run.sh --old    counter-proof: runs this gate against the tree BEFORE the bar (OLD_REF); it must fail
#
# What is measured (serial trace of the window: rects, texts, tooltips):
#   1. ONE bar: >= 10 icon buttons (side list, open, page up/down, zoom -/+, fit width, fit page, match up/down)
#      share one row (same centre line), the search field sits on that line too, nothing sticks out of the window
#   2. tooltips of the icon buttons exist (the word and the key: "Vergrößern (+)")
#   3. no path field while a document is open (it is a second row only without a document / after Open)
#   4. key F4: the page list opens at the left, the page area gets narrower -> the fit-width zoom goes DOWN, row "Seite 2"
#   5. no document: path field + "Öffnen" button are there
#   6. Ctrl+F puts the cursor into the search field, typing "wasser" + Enter -> "Treffer 1 von 8"
#   7. the picture: icons are drawn in the bar (ink in the bar's strip), the page below is drawn
set -uo pipefail
OLD_REF=7f9c4eae
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
if [ "${1:-}" = "--old" ]; then
    D=$(mktemp -d); trap 'git -C "$ROOT" worktree remove --force "$D/t" >/dev/null 2>&1; rm -rf "$D"' EXIT
    git -C "$ROOT" worktree add --detach "$D/t" "$OLD_REF" >/dev/null 2>&1 || { echo "PDFBAR --old: cannot check out $OLD_REF"; exit 2; }
    mkdir -p "$D/t/tools/pdfbar"; cp "$ROOT/tools/pdfbar/run.sh" "$D/t/tools/pdfbar/run.sh"
    ( cd "$D/t" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1; OUT="$D/out" bash tools/pdfbar/run.sh ) > "$D/old.txt" 2>&1
    f=$(grep -c '^  FAIL' "$D/old.txt"); o=$(grep -c '^  OK' "$D/old.txt")
    tail -n 4 "$D/old.txt"
    if [ "$f" -ge 4 ]; then echo "PDFBAR --old: the old viewer fails $f checks ($o ok) -- counter-proof holds"; exit 0; fi
    echo "PDFBAR --old: the old viewer passes too much ($f fail, $o ok)"; exit 1
fi
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-$(mktemp -d)}
[ -n "${KEEP:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT/c"
. tools/lib/sperre.sh && osum_sperre "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v python3 >/dev/null 2>&1 || { echo "PDFBAR: skipped, python3 is missing"; exit 0; }
FONTB="$ROOT/assets/osum-sans-bold.ttf"; FONTS="$ROOT/assets/osum-serif.ttf"; FONTSB="$ROOT/assets/osum-serif-bold.ttf"
python3 tools/pdf/corpus.py "$OUT/c" > "$OUT/corpus.log" 2>&1 || { echo "PDFBAR: corpus.py failed"; tail -3 "$OUT/corpus.log"; exit 1; }

win() { # name pdf-or-none mon-args...
    local n=$1 pdf=$2; shift 2
    local extra="wigapp=/bin/pdfview"; local xf=()
    if [ "$pdf" != none ]; then extra="wigapp=/bin/pdfview,/t.pdf"; xf=("xfile=/t.pdf=$OUT/c/$pdf.pdf"); fi
    ALLTAGBUILD="$OUT/bd" bash tools/alltag/build.sh "$OUT/w-$n" accel=kvm desk=no uitrace=yes warten=6 \
        extra="$extra" progs="pdfview sh echo ls cat" "${xf[@]}" \
        xfile=/lib/bold.ttf="$FONTB" xfile=/lib/serif.ttf="$FONTS" xfile=/lib/serifb.ttf="$FONTSB" "$@" > "$OUT/w-$n.log" 2>&1
}
# the last batch of rects of a serial log: "id kind x y w h" per line
rects() {
    python3 - "$1" <<'PY'
import re, sys
batch = []; prev = False
for ln in open(sys.argv[1], errors="replace"):
    m = re.search(r"pdfview: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ln)
    if m:
        if not prev: batch = []
        batch.append(tuple(int(v) for v in m.groups())); prev = True
    else:
        prev = False
for r in batch: print(*r)
PY
}

win a basic
SA="$OUT/w-a/serial.txt"; rects "$SA" > "$OUT/a.rects"
echo "== 1. one bar =="
nb=$(awk '$2==7' "$OUT/a.rects" | wc -l)
[ "$nb" -ge 10 ] && ok "$nb icon buttons in the window" || bad "only $nb icon buttons (need >= 10)"
rows=$(awk '$2==7 {print $4+int($6/2)}' "$OUT/a.rects" | sort -u | wc -l)
[ "$rows" = 1 ] && [ "$nb" -ge 10 ] && ok "all icon buttons share ONE centre line" || bad "icon buttons on $rows lines"
ec=$(awk '$2==4 {print $4+int($6/2)}' "$OUT/a.rects" | head -1); bc=$(awk '$2==7 {print $4+int($6/2)}' "$OUT/a.rects" | head -1)
[ -n "$ec" ] && [ -n "$bc" ] && [ $((ec-bc)) -le 1 ] && [ $((bc-ec)) -le 1 ] && ok "the search field sits on the same line (centre $ec vs $bc)" || bad "search field line '$ec' vs buttons '$bc'"
over=$(awk '($3+$5)>900 {n++} END {print n+0}' "$OUT/a.rects")
[ "$over" = 0 ] && [ "$nb" -ge 10 ] && ok "nothing sticks out of the 900-wide window" || bad "$over controls reach past the window"
echo "== 2. tooltips =="
for w in "Seitenliste" "Vergrößern (+)" "Verkleinern (-)" "An Breite anpassen (b)" "Voriger Treffer (p)" "Nächster Treffer (n)" "Datei öffnen (Strg+O)"; do
    grep -aq "fuiscene: tip key=.*$w" "$SA" && ok "tooltip: $w" || bad "no tooltip '$w'"
done
echo "== 3. window with a document =="
grep -aq 'wlib: text .*t=Seite 1 von 2' "$SA" && ok "page counter 'Seite 1 von 2'" || bad "no page counter"
na=$(awk '$2==4' "$OUT/a.rects" | wc -l)
[ "$na" = 1 ] && ok "only the search field (no path field with a document open)" || bad "$na text fields (expected 1)"
za=$(grep -ao 't=[0-9]*%' "$SA" | tail -1 | tr -dc 0-9)
if [ -s "$OUT/w-a/desktop.ppm" ]; then
python3 - "$OUT/w-a/desktop.ppm" > "$OUT/a.ink" 2>/dev/null <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
bar = im.crop((50, 56, 760, 98)); page = im.crop((60, 130, 920, 700))
print(sum(1 for v in bar.getdata() if v < 120), sum(1 for v in page.getdata() if v < 100))
PY
fi
read -r inkbar inkpage < "$OUT/a.ink" 2>/dev/null || true
[ "${inkbar:-0}" -gt 150 ] && ok "the bar is drawn (icon ink $inkbar px)" || bad "the bar strip is empty (${inkbar:-?})"
[ "${inkpage:-0}" -gt 800 ] && ok "the page is drawn ($inkpage dark px)" || bad "the page area is empty (${inkpage:-?})"

echo "== 4. page list (key F4) =="
win b basic 'mon=sleep 1' 'mon=sendkey f4' 'mon=sleep 2'
SB="$OUT/w-b/serial.txt"
zb=$(grep -ao 't=[0-9]*%' "$SB" | tail -1 | tr -dc 0-9)
[ -n "$za" ] && [ -n "$zb" ] && [ "$zb" -lt "$za" ] && ok "page area narrower with the list: fit width $za % -> $zb %" || bad "zoom '$za' -> '$zb' (list did not take room)"
rects "$SB" | awk '$2==6 && $5==120' | grep -q . && ok "the page list (a list of 120 wide) is there" || bad "no page list rect in the window"

echo "== 5. no document =="
win c none
SCN="$OUT/w-c/serial.txt"; rects "$SCN" > "$OUT/c.rects"
nc=$(awk '$2==4' "$OUT/c.rects" | wc -l)
[ "$nc" = 2 ] && ok "path field + search field (2 text fields)" || bad "$nc text fields without a document (expected 2)"
grep -aq 'wlib: text .*t=Öffnen' "$SCN" && ok "the Öffnen button is there" || bad "no Öffnen button"

echo "== 6. Ctrl+F, type, Enter =="
win d search 'mon=sleep 1' 'mon=sendkey ctrl-f' 'mon=sleep 1' 'mon=sendkey w' 'mon=sendkey a' 'mon=sendkey s' 'mon=sendkey s' 'mon=sendkey e' 'mon=sendkey r' 'mon=sendkey ret' 'mon=sleep 3'
SD="$OUT/w-d/serial.txt"
grep -aq 'wlib: text .*t=Treffer 1 von 8' "$SD" && ok "Ctrl+F + 'wasser' + Enter: 'Treffer 1 von 8'" || bad "no 'Treffer 1 von 8' after Ctrl+F and typing"

echo
echo "=================================================================="
echo "  PDFBAR: $pass passed, $fail failed"
echo "=================================================================="
[ "$fail" = 0 ]
