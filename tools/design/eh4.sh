#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/eh4.sh <ausgabeverzeichnis>
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:?usage: eh4.sh <outdir>}
mkdir -p "$OUT"
HALT=${DESIGNHALT:-420}

echo "== build (once, so the runs do not fight over the build directory) =="
bash tools/design/capture.sh "$OUT/bau" nurbau=ja || exit 1

# lauf <name> <extra-woerter> <weitere key=value> <drehbuch>
lauf() {
    local name=$1 extra=$2 kv=$3 buch=$4
    mkdir -p "$OUT/$name"
    printf '%s\n' "$buch" > "$OUT/$name.dreh"
    # shellcheck disable=SC2086
    bash tools/design/capture.sh "$OUT/$name" halt="$HALT" \
        extra="$extra" drehbuch="$OUT/$name.dreh" $kv \
        > "$OUT/$name.log" 2>&1
    echo "   fertig: $name ($(ls "$OUT/$name"/*.ppm 2>/dev/null | wc -l) Bilder)"
}

#
GRUND='warte 14
foto 01-schreibtisch
taste meta_l
warte 8
foto 02-startmenue
tippe term
warte 8
foto 03-trefferliste
taste esc
warte 6
foto 04-menue-zu'

echo "== four base runs, simultaneously =="
lauf hell-1280   "" "res=1280x800 mode=light scheme=day" "$GRUND" &
lauf hell-2560   "" "res=2560x1440 uiscale=2 mode=light scheme=day" "$GRUND" &
lauf dunkel-1280 "" "res=1280x800 mode=dark scheme=day dark_scheme=midnight" "$GRUND" &
lauf dunkel-2560 "" "res=2560x1440 uiscale=2 mode=dark scheme=day dark_scheme=midnight" "$GRUND" &

#
MENUE='warte 14
foto 01-ohne-menue
taste meta_l
warte 8
foto 02-super-offen
taste esc
warte 8
foto 03-escape-weg
klickauf start
warte 8
foto 04-logo-offen
klick 900,260
warte 8
foto 05-klick-daneben-weg'
lauf menue-2560 "" "res=2560x1440 uiscale=2" "$MENUE" &

# ----------------------------------------------------- der Mauszeiger
#
ZEIGER='warte 14
fahre 700,240
warte 4
foto 01-zeiger-schreibtisch
taste meta_l
warte 8
fahre 120,180
warte 4
foto 02-zeiger-suchfeld
warte 2
foto 03-zeiger-liste'
lauf zeiger-1280 "" "res=1280x800 mode=light" "$ZEIGER" &
lauf zeiger-2560 "" "res=2560x1440 uiscale=2 mode=light" "$ZEIGER" &
lauf zeigerd-2560 "" "res=2560x1440 uiscale=2 mode=dark dark_scheme=midnight" "$ZEIGER" &
wait

# ------------------------------------------------------- einsammeln
echo "== einsammeln =="
mkdir -p "$OUT/bilder"
for d in hell-1280 hell-2560 dunkel-1280 dunkel-2560 menue-2560 \
         zeiger-1280 zeiger-2560 zeigerd-2560; do
    mkdir -p "$OUT/bilder/$d"
    for f in "$OUT/$d"/*.ppm; do
        [ -e "$f" ] || continue
        python3 tools/design/ppm2png.py "$f" \
            "$OUT/bilder/$d/$(basename "$f" .ppm).png" >/dev/null 2>&1 \
            || python3 - "$f" "$OUT/bilder/$d/$(basename "$f" .ppm).png" <<'PY'
import sys
from PIL import Image
Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2])
PY
    done
    [ -e "$OUT/$d/serial.txt" ] && cp "$OUT/$d/serial.txt" "$OUT/bilder/$d/serial.txt"
done
find "$OUT" -name '*.ppm' -delete

echo "== messen =="
python3 tools/design/eh4measure.py "$OUT" | tee "$OUT/BEFUND.txt"
echo "== fertig: $OUT/bilder =="
