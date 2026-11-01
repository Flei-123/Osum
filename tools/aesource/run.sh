#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export LC_ALL=C.UTF-8
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SRC=tools/aesource/aesource.txt

echo "== 1. boot, cat a file with real German umlauts in the terminal window =="
bash tools/design/eh6.sh "$TMPD/run" accel=kvm "xfile=/etc/aesource.txt=$SRC" \
    drehbuch=tools/aesource/script.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
P="$TMPD/run/01-ae.ppm"
[ -s "$P" ] && ok "picture taken" || bad "picture missing: $(tail -2 "$TMPD/run.log" | tr '\n' ' ')"

echo "== 2. the cells hold the umlaut code points =="
python3 tools/aesource/check.py "$S" "$SRC" | sed 's/^/        /' > "$TMPD/cells.txt"
cat "$TMPD/cells.txt"
python3 tools/aesource/check.py "$S" "$SRC" > /dev/null \
    && ok "every source line stands in the cells with its umlaut code points" \
    || bad "a source line is missing or no wide cell was reported"
grep -aq 'wm: termwide .* 196$' "$S" && ok "U+00C4 (A umlaut) is a cell" || bad "no U+00C4 cell"
grep -aq 'wm: termwide .* 214$' "$S" && ok "U+00D6 (O umlaut) is a cell" || bad "no U+00D6 cell"
grep -aq 'wm: termwide .* 220$' "$S" && ok "U+00DC (U umlaut) is a cell" || bad "no U+00DC cell"
grep -aq 'wm: termwide .* 223$' "$S" && ok "U+00DF (sharp s) is a cell" || bad "no U+00DF cell"

echo "== 3. the pixels of the umlaut rows are exact =="
GEO=$(grep -a '^wm: termgeo' "$S" | tail -n 1)
PXL=$(grep -a '^wm: termgitter' "$S" | tail -n 1 | grep -oE ' px=[0-9]+' | grep -oE '[0-9]+')
g() { printf '%s' "$GEO" | grep -oE " $1=[0-9]+" | grep -oE '[0-9]+'; }
CX=$(g cx); CY=$(g cy); CW=$(g cw); CH=$(g ch); FG=$(g fg); BG=$(g bg)
echo "        $GEO px=${PXL:-?}"
[ -n "$CX" ] && [ -n "$PXL" ] && ok "terminal geometry and font size reported" || bad "geometry missing"
rgb() { echo "$(($1>>16&255)) $(($1>>8&255)) $(($1&255))"; }
tgrid() {
    python3 tools/gfx/checkshot.py tgrid "$P" assets/osum-mono.ttf "${PXL:-16}" "${CX:-0}" "${CY:-0}" \
        "${CW:-10}" "${CH:-19}" "$1" 0 $(rgb "${FG:-0}") $(rgb "${BG:-0}") "$2" 0 2>&1 | head -1
}
wrong() { printf '%s' "$1" | grep -oE '[0-9]+ wrong' | grep -oE '^[0-9]+'; }
ink() { printf '%s' "$1" | grep -oE '[0-9]+ ink pixels' | grep -oE '^[0-9]+'; }
while IFS= read -r line; do
    row=$(grep -a "^        ROW [0-9]* $line\$" "$TMPD/cells.txt" | head -1 | awk '{print $2}')
    if [ -z "$row" ]; then bad "row of '$line' not found"; continue; fi
    out=$(tgrid "$row" "$line")
    echo "        $line -> $out"
    w=$(wrong "$out"); n=$(ink "$out")
    [ "${w:-99}" = 0 ] && ok "'$line' is pixel-exact" || bad "'$line': ${w:-?} wrong pixels"
    [ "${n:-0}" -ge 500 ] && ok "ink measured ($n)" || bad "too little ink (${n:-0})"
done < "$SRC"

echo "== 4. controls =="
ROW1=$(grep -a '^        ROW [0-9]* AE1 ' "$TMPD/cells.txt" | head -1 | awk '{print $2}')
if [ -n "$ROW1" ]; then
    c1=$(wrong "$(tgrid "$ROW1" 'AE1 ÖPFEL ÖL ÜBER ÄRGER')")
    [ "${c1:-0}" -gt 0 ] && ok "CONTROL: a wrong umlaut (O instead of A) does NOT fit ($c1 wrong)" || bad "CONTROL: wrong umlaut still fits"
    c2=$(wrong "$(tgrid "$ROW1" 'AE1 ÄPFEL ÖL ÜBR ÄRGER')")
    [ "${c2:-0}" -gt 0 ] && ok "CONTROL: a missing letter does NOT fit ($c2 wrong)" || bad "CONTROL: missing letter still fits"
else
    bad "CONTROL: no row for AE1"
fi
grep -av '^wm: termwide ' "$S" > "$TMPD/serial.nowide"
python3 tools/aesource/check.py "$TMPD/serial.nowide" "$SRC" > /dev/null 2>&1 \
    && bad "CONTROL: dump without wide cells still passes" \
    || ok "CONTROL: dump without wide cells is red"

mkdir -p docs/shots/aesource
python3 tools/design/ppm2png.py "$P" docs/shots/aesource/01-ae.png > /dev/null 2>&1

echo
echo "AESOURCE: $pass passed, $fail failed"
[ "$fail" = 0 ]
