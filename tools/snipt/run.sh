#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
B=tools/alltag/build.sh
[ -e /dev/kvm ] && export OSUM_ACCEL=${OSUM_ACCEL:-kvm}

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 val=$2 op=$3 want=$4
    if [ -z "${val:-}" ]; then bad "$name: no number (want $op $want)"; return; fi
    if [ "$val" -"$op" "$want" ] 2>/dev/null; then ok "$name: $val"
    else bad "$name: $val, want $op $want"; fi
}
has()  { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -qaF "$2" "$1" 2>/dev/null && bad "$3 -- '$2' present" || ok "$3"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SNIPT: skipped, no qemu"; exit 0; }
python3 -c "import PIL" 2>/dev/null || { echo "SNIPT: skipped, no Pillow"; exit 0; }

PROGS="desktop taskbar launcher settings theme explorer snipt sh echo ls cat"
SW=1280
SH=800

cmp_png() {
python3 -W ignore - "$@" <<'PY'
import sys
from PIL import Image, ImageChops
png, ppm = sys.argv[1], sys.argv[2]
x, y, w, h = map(int, sys.argv[3:7])
try:
    a = Image.open(png); a.verify(); a = Image.open(png).convert("RGB")
    b = Image.open(ppm).convert("RGB").crop((x, y, x + w, y + h))
except Exception:
    print(-1); sys.exit(0)
if a.size != b.size:
    print(-2); sys.exit(0)
d = ImageChops.difference(a, b)
same = sum(1 for p in d.getdata() if p == (0, 0, 0))
print(same * 1000 // (w * h))
PY
}

field() { grep -a "$2" "$1" | head -1 | sed -n "s/.* $3=\([0-9]*\).*/\1/p"; }

drag_script() {
    local f=$1
    {
        echo "sendkey meta_l-shift-s"
        echo "warte 14"
        for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "mouse_move -120 -120"; done
        echo "warte 1"
        for i in 1 2 3; do echo "mouse_move 100 100"; done
        for i in 1 2 3 4 5 6 7; do echo "mouse_move 100 0"; done
        echo "warte 1"
        echo "mouse_button 1"
        echo "warte 1"
        for i in 1 2 3 4; do echo "mouse_move 50 30"; echo "warte 0.3"; done
        echo "mouse_button 0"
        echo "warte 14"
    } > "$f"
}

mons() { local f=$1 a=()
    while IFS= read -r l; do [ -n "$l" ] && a+=("mon=$l"); done < "$f"
    printf '%s\0' "${a[@]}"
}

run_keys() { local dir=$1 script=$2
    local args=()
    while IFS= read -r -d '' x; do args+=("$x"); done < <(mons "$script")
    bash "$B" "$dir" kbd=yes warten=3 extra="wighalt=75" progs="$PROGS" "${args[@]}" > "$dir.log" 2>&1
}

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc failed"; exit 1; }
if bash "$B" "$OUT/b0" script='echo ready;exit' progs="$PROGS" > "$OUT/build.log" 2>&1; then
    ok "kernel and programs built"
else
    bad "build failed"; tail -20 "$OUT/build.log"; exit 1
fi

echo
echo "== 2. Win+Shift+S, drag a rectangle =="
drag_script "$OUT/drag.txt"
run_keys "$OUT/a" "$OUT/drag.txt"
S="$OUT/a/serial.txt"
has "$S" "hk: super+S" "driver latched Win+Shift+S"
has "$S" "snipt: ready" "overlay is up"
has "$S" "snipt: saved /bilder/Screenshots/Screenshot-1.png" "PNG saved in Screenshots"
X=$(field "$S" 'snipt: saved' x); Y=$(field "$S" 'snipt: saved' y)
W=$(field "$S" 'snipt: saved' w); H=$(field "$S" 'snipt: saved' h)
num "selection x" "$X" ge 650
num "selection width (about 200)" "$W" ge 150
num "selection width max" "$W" le 250
num "selection height (about 120)" "$H" ge 90
num "selection height max" "$H" le 150
python3 tools/osum/mkfs.py cat "$OUT/a/disk.img" /bilder/Screenshots/Screenshot-1.png > "$OUT/a.png" 2>/dev/null
if [ -n "$W" ] && [ -n "$H" ]; then
    G=$(cmp_png "$OUT/a.png" "$OUT/a/desktop.ppm" "$X" "$Y" "$W" "$H")
    num "PNG pixels equal to the host crop (promille)" "$G" ge 900
    N=$(cmp_png "$OUT/a.png" "$OUT/a/desktop.ppm" 40 100 "$W" "$H")
    num "crop of another place must differ (counter-proof, promille)" "$N" lt 900
fi
T=$(grep -a 'snipt: clip typ=' "$S" | head -1 | sed 's/.*typ=//' | tr -dc '0-9')
if [ -n "$T" ] && [ $(( T & 8 )) -ne 0 ]; then ok "clipboard holds an IMAGE entry (type $T)"; else bad "clipboard type '$T' has no image bit"; fi
has "$S" "snipt: toast:" "toast posted"
num "exactly one file for one selection" "$(grep -ac 'snipt: saved' "$S")" eq 1

echo
echo "== 3. Esc cancels =="
{
    echo "sendkey meta_l-shift-s"
    echo "warte 14"
    echo "sendkey esc"
    echo "warte 10"
} > "$OUT/esc.txt"
run_keys "$OUT/e" "$OUT/esc.txt"
S="$OUT/e/serial.txt"
has "$S" "snipt: ready" "overlay is up"
has "$S" "snipt: cancel" "Esc cancelled"
hasnt "$S" "snipt: saved" "nothing saved after Esc"

echo
echo "== 4. toolbar: Window mode, Full button =="
{
    echo "sendkey meta_l-shift-s"
    echo "warte 14"
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "mouse_move -120 -120"; done
    echo "warte 1"
    echo "mouse_move 100 0"
    echo "mouse_move 100 0"
    echo "mouse_move 100 0"
    echo "mouse_move 100 0"
    echo "mouse_move 100 0"
    echo "mouse_move 70 42"
    echo "warte 1"
    echo "mouse_button 1"
    echo "mouse_button 0"
    echo "warte 3"
    echo "mouse_move 140 0"
    echo "warte 1"
    echo "mouse_button 1"
    echo "mouse_button 0"
    echo "warte 14"
} > "$OUT/bar.txt"
run_keys "$OUT/f" "$OUT/bar.txt"
S="$OUT/f/serial.txt"
has "$S" "snipt: mode 1" "Window button switched the mode"
has "$S" "snipt: saved /bilder/Screenshots/Screenshot-1.png x=0 y=0 w=$SW h=$SH" "Full button captured the whole screen"

echo
echo "== 5. command line: geometry and quick =="
bash "$B" "$OUT/c" desk=no warten=14 progs="snipt sh echo ls cat theme" \
    extra="wigapp=/bin/snipt,-g,100,50,320,200,-o,/r.png" > "$OUT/c.log" 2>&1
S="$OUT/c/serial.txt"
has "$S" "snipt: saved /r.png x=100 y=50 w=320 h=200" "exactly the rectangle"
python3 tools/osum/mkfs.py cat "$OUT/c/disk.img" /r.png > "$OUT/c.png" 2>/dev/null
G=$(cmp_png "$OUT/c.png" "$OUT/c/desktop.ppm" 100 50 320 200)
num "region pixels equal to the host crop (promille)" "$G" ge 900
bash "$B" "$OUT/d" desk=no warten=14 progs="snipt sh echo ls cat theme" \
    extra="wigapp=/bin/snipt,-g,1200,50,320,200,-o,/bad.png" > "$OUT/d.log" 2>&1
has "$OUT/d/serial.txt" "snipt: bad region" "out-of-range region refused"
hasnt "$OUT/d/serial.txt" "snipt: saved" "nothing saved for the bad region"

echo
echo "== 6. rules =="
Z=$(cat kernel/user/snipt.fi kernel/user/snipgrab.fi kernel/user/snipsave.fi | grep -ac 'wlibc\.\(px\|rect\|rrect\|frame\|hline\|vline\|text\|glyph\|blit\)(' || true)
num "direct draw calls outside fuiscene" "$Z" eq 0

echo
echo "== SNIPT: $pass green, $fail red =="
[ "$fail" -eq 0 ]
