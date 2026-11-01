#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/runde.sh <ausgabeverzeichnis> [shape=..] [scheme=..]
#                              [mode=..] [res=..] [accel=..]
#
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:?usage: runde.sh <outdir> [key=value ...]}
shift || true
mkdir -p "$OUT"

ARGS=("$@")
HALT=${DESIGNHALT:-300}

echo "== bauen (einmal) =="
bash tools/design/capture.sh "$OUT/bau" nurbau=ja "${ARGS[@]}" || exit 1

lauf() { # name  extra-woerter  drehbuch-inhalt
    local name=$1 extra=$2 buch=$3
    printf '%s\n' "$buch" > "$OUT/$name.dreh"
    bash tools/design/capture.sh "$OUT/$name" halt="$HALT" \
        extra="$extra" drehbuch="$OUT/$name.dreh" "${ARGS[@]}" \
        > "$OUT/$name.log" 2>&1
}

echo "== fuenf Starts, gleichzeitig =="
lauf tisch  "nostart" "warte 12
foto 01-schreibtisch" &
lauf start  "" "warteauf launcher: ready || 200
warte 6
foto 02-startmenue" &
lauf datei  "nostart wigapp=/bin/explorer" "warteauf explorer: ready || 200
warte 10
foto 03-explorer
klickauf fmbar0
warteauf explorer: menurect || 40
warte 5
klickauf emenue0
warteauf explorer: dlgrect || 40
warte 6
foto 04-dialog" &
lauf zentrum "nostart" "warte 12
klickauf netz
warte 8
foto 05-kontrollzentrum" &
lauf einst  "nostart einst" "warteauf settings: ready || 200
warte 8
foto 06-einstellungen" &
wait

echo "== einsammeln =="
mkdir -p "$OUT/bilder"
for d in tisch start datei zentrum einst; do
    for f in "$OUT/$d"/*.ppm; do
        [ -e "$f" ] || continue
        cp "$f" "$OUT/bilder/"
        [ -e "$OUT/$d/serial.txt" ] && \
            cp "$OUT/$d/serial.txt" "$OUT/bilder/$(basename "$f" .ppm).serial"
    done
    [ -e "$OUT/$d/serial.txt" ] && cp "$OUT/$d/serial.txt" "$OUT/bilder/$d-serial.txt"
done
python3 - "$OUT" <<'PY'
import os, re, sys
o = sys.argv[1]
ser = os.path.join(o, "tisch", "serial.txt")
src = os.path.join(o, "bilder", "01-schreibtisch.ppm")
if os.path.exists(ser) and os.path.exists(src):
    t = open(ser, "rb").read().decode("latin1")
    m = None
    for m in re.finditer(
            r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t):
        pass
    if m:
        x, y, w, h = (int(m.group(i)) for i in (1, 2, 3, 4))
        from PIL import Image
        im = Image.open(src).convert("RGB")
        im.crop((x, y, x + w, y + h)).save(
            os.path.join(o, "bilder", "07-taskleiste.png"))
        print("07-taskleiste %dx%d aus (%d,%d)" % (w, h, x, y))
PY
cat "$OUT"/bilder/*-serial.txt > "$OUT/bilder/serial.txt" 2>/dev/null
python3 - "$OUT/bilder" <<'PY'
import glob, os, sys
from PIL import Image
o = sys.argv[1]
for p in sorted(glob.glob(os.path.join(o, "*.ppm"))):
    im = Image.open(p).convert("RGB")
    im.save(p[:-4] + ".png")
    print("bild %s %dx%d farben=%d" % (os.path.basename(p)[:-4],
          im.size[0], im.size[1], len(im.getcolors(maxcolors=1 << 24) or [])))
PY
echo "== fertig: $OUT/bilder =="
ls "$OUT/bilder"/*.png 2>/dev/null | wc -l
