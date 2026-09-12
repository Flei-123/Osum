#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/eh4.sh -- DIE ABNAHME DER RUNDE ECHTHARDWARE-4.
#
#   bash tools/design/eh4.sh <ausgabeverzeichnis>
#
# WARUM ES DIESEN LAEUFER GIBT UND NICHT runde.sh GENUEGT.  Justin hat
# an den Belegen der Vorrunde vier Dinge nachgewiesen, die runde.sh
# nicht pruefen KANN, weil sie in seinen Aufrufen gar nicht vorkommen:
#
#   1. Die Ordner hiessen "2560", der Lauf war aber Vervielfachung 1
#      -- `capture.sh` hat `uiscale=` nie auf die Kommandozeile
#      geschrieben.  Gemessen: Leiste 39 Bildpunkte hoch auf einem
#      1440p-Schirm.  Hier steht `uiscale=2` in JEDEM 2560er Lauf,
#      und die gemessene Leistenhoehe steht im Bericht.
#   2. Der Dunkelmodus las die blaue Slate-Rampe, weil `dark_scheme=`
#      nicht in der theme.conf stand.  Hier steht es (`midnight`,
#      Zinc), und `blaustich.py` rechnet den Blaustich nach.
#   3. "Search programs" klebte auf JEDEM Bild unten links.  Hier gibt
#      es die Bildserie, die zeigt, dass es das nicht mehr tut:
#      Schreibtisch leer -> Super -> Escape -> Klick aufs Logo ->
#      Klick daneben.
#   4. Der Mauszeiger war eine 12x18-Bitmaske, blockweise vergroessert.
#      Hier steht er ueber hellem Grund, ueber dunklem Grund, ueber
#      einem Textfeld und an einem Fensterrand, je vergroessert.
#
# Jeder Lauf ist eine eigene Maschine, alle laufen GLEICHZEITIG -- der
# Grund steht in runde.sh und gilt unveraendert.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:?usage: eh4.sh <outdir>}
mkdir -p "$OUT"
HALT=${DESIGNHALT:-420}

echo "== bauen (einmal, damit sich die Laeufe nicht um das Bauverzeichnis streiten) =="
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

# --------------------------------------------------- die vier Grundlaeufe
#
# Ein Drehbuch fuer alle vier: Schreibtisch, Leiste, Startmenue (per
# Super, nicht weil es von selbst offen steht), eine Trefferliste und
# ein Programmfenster.  Dieselbe Folge in hell und dunkel, in 1280 und
# in 2560 -- nur so ist ein Vergleich einer.
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

echo "== vier Grundlaeufe, gleichzeitig =="
lauf hell-1280   "" "res=1280x800 mode=light scheme=day" "$GRUND" &
lauf hell-2560   "" "res=2560x1440 uiscale=2 mode=light scheme=day" "$GRUND" &
lauf dunkel-1280 "" "res=1280x800 mode=dark scheme=day dark_scheme=midnight" "$GRUND" &
lauf dunkel-2560 "" "res=2560x1440 uiscale=2 mode=dark scheme=day dark_scheme=midnight" "$GRUND" &

# ------------------------------------------- die Serie zum Startmenue
#
# Justins Punkt 1 in Bildern.  Zwischen jedem Schritt ein Foto, und die
# Behauptung "im Normalzustand ist es NICHT sichtbar" ist damit eine
# Messung: auf 01 und 03 und 05 darf an der Stelle des Menues nichts
# stehen, auf 02 und 04 muss dort etwas stehen.
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
# Vier Stellen, an denen der Zeiger etwas anderes sein muss: leerer
# Schreibtisch (Pfeil), Leiste (Hand ueber einem Knopf), Suchfeld des
# Starters (Textmarke), rechter Fensterrand (Doppelpfeil waagrecht).
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
# Die PPM sind nach der Umwandlung entbehrlich und kosten ein Vielfaches
# der PNG. Die Platte dieses Servers stand bei 97 Prozent, als diese
# Runde anfing -- das ist kein theoretischer Grund.
find "$OUT" -name '*.ppm' -delete

echo "== messen =="
python3 tools/design/eh4mess.py "$OUT" | tee "$OUT/BEFUND.txt"
echo "== fertig: $OUT/bilder =="
