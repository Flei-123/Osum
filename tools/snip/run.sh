#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/snip/run.sh -- L-008 (r762): THE SCREENSHOT TOOL ACCEPTANCE.
#
#   bash tools/snip/run.sh [workdir]
#
# What is measured (each with an outside witness, no "looks fine"):
#
#   1. BUILD       kernel + programs (via tools/alltag/build.sh, same VM harness).
#   2. PRINT KEY   monitor `sendkey print` in a booted desktop: the keyboard
#                  driver latches it (`hk: print`), the taskbar starts
#                  `/bin/snip -q`, which writes /bilder/Screenshots/Screenshot-1.png
#                  and puts an IMAGE entry (type bit 8) on the clipboard bus.
#                  The PNG is read from the guest disk by the HOST (mkfs.py cat),
#                  opened with Pillow (valid PNG, 1280x800) and compared pixel by
#                  pixel to QEMU's own screendump of the same screen.
#   3. WIN+SHIFT+S `sendkey meta_l-shift-s`: latched as `hk: super+S`, the taskbar
#                  starts `snip -r`; the region window comes up (`snip: ready`)
#                  with the frozen picture.
#   4. REGION      `snip -g x y w h -o file`: exactly that rectangle, host crop of
#                  the screendump == the PNG (pixels), size == w x h.
#   5. RULES       no direct draw calls outside wlib in snip.fi.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
B=tools/alltag/build.sh

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 val=$2 op=$3 want=$4
    if [ -z "${val:-}" ]; then bad "$name: no number (want $op $want)"; return; fi
    if [ "$val" -"$op" "$want" ] 2>/dev/null; then ok "$name: $val"
    else bad "$name: $val, want $op $want"; fi
}
has()    { grep -qaF "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 -- '$2' missing"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "SNIP: skipped, no qemu"; exit 0; }
python3 -c "import PIL" 2>/dev/null || { echo "SNIP: skipped, no Pillow"; exit 0; }

PROGS="desktop taskbar launcher settings theme explorer snip sh echo ls cat"

# compare a guest PNG with a window of the host screendump; prints promille equal, or -1/-2
cmp_png() { # png ppm x y w h
python3 - "$@" <<'PY'
import sys
from PIL import Image, ImageChops
png, ppm = sys.argv[1], sys.argv[2]
x, y, w, h = map(int, sys.argv[3:7])
try:
    a = Image.open(png); a.verify(); a = Image.open(png).convert("RGB")
    b = Image.open(ppm).convert("RGB").crop((x, y, x + w, y + h))
except Exception as e:
    print(-1); sys.exit(0)
if a.size != b.size:
    print(-2); sys.exit(0)
d = ImageChops.difference(a, b)
same = sum(1 for p in d.getdata() if p == (0, 0, 0))
print(same * 1000 // (w * h))
PY
}

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc failed"; exit 1; }
if bash "$B" "$OUT/b0" script='echo ready;exit' progs="$PROGS" > "$OUT/build.log" 2>&1; then
    ok "kernel and programs built"
else
    bad "build failed"; tail -20 "$OUT/build.log"; exit 1
fi

echo
echo "== 2. Print key: full screen, file, clipboard =="
bash "$B" "$OUT/a" kbd=yes warten=3 extra="wighalt=75" progs="$PROGS" \
    mon="sendkey print" mon="warte 25" > "$OUT/a.log" 2>&1
S="$OUT/a/serial.txt"
has "$S" "hk: print" "driver latched the Print key"
has "$S" "snip: gesichert /bilder/Screenshots/Screenshot-1.png w=1280 h=800" "tool wrote the file, full screen"
T=$(grep -a 'snip: clip typ=' "$S" | head -1 | sed 's/.*typ=//' | tr -dc '0-9')
if [ -n "$T" ] && [ $(( T & 8 )) -ne 0 ]; then ok "clipboard holds an IMAGE entry (type $T)"; else bad "clipboard type '$T' has no image bit"; fi
python3 tools/osum/mkfs.py cat "$OUT/a/disk.img" /bilder/Screenshots/Screenshot-1.png > "$OUT/a.png" 2>/dev/null
G=$(cmp_png "$OUT/a.png" "$OUT/a/desktop.ppm" 0 0 1280 800)
num "PNG valid + pixels equal to QEMU's screendump (promille)" "$G" ge 950
N=$(grep -ac 'snip: gesichert' "$S")
num "exactly one file for one key press" "$N" eq 1

echo
echo "== 3. Win+Shift+S: region window =="
bash "$B" "$OUT/b" kbd=yes warten=3 extra="wighalt=75" progs="$PROGS" \
    mon="sendkey meta_l-shift-s" mon="warte 25" > "$OUT/b.log" 2>&1
S="$OUT/b/serial.txt"
has "$S" "hk: super+S" "driver latched Win+Shift+S"
has "$S" "snip: ready" "region window is up"
G=$(grep -a 'snip: geom w=' "$S" | head -1 | sed 's/.*w=//' | cut -d' ' -f1 | tr -dc '0-9')
num "region window covers the screen (width)" "$G" ge 1200

echo
echo "== 4. region by geometry =="
bash "$B" "$OUT/c" desk=no warten=14 progs="snip sh echo ls cat theme" \
    extra="wigapp=/bin/snip,-g,100,50,320,200,-v,2,-o,/r.png" > "$OUT/c.log" 2>&1
S="$OUT/c/serial.txt"
has "$S" "snip: gesichert /r.png w=320 h=200" "tool wrote exactly the rectangle"
python3 tools/osum/mkfs.py cat "$OUT/c/disk.img" /r.png > "$OUT/c.png" 2>/dev/null
G=$(cmp_png "$OUT/c.png" "$OUT/c/desktop.ppm" 100 50 320 200)
num "region pixels equal to the host crop (promille; 972 measured, a transient window differs between capture and screendump)" "$G" ge 950

echo
echo "== 5. rules =="
Z=$(grep -ac 'wlibc\.\(px\|rect\|rrect\|frame\|hline\|vline\|text\|glyph\|blit\)(' kernel/user/snip.fi || true)
num "direct draw calls outside wlib in snip.fi" "$Z" eq 0

echo
echo "== SNIP: $pass green, $fail red =="
[ "$fail" -eq 0 ]
