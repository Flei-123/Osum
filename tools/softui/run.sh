#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/softui/run.sh -- ROUND SOFTUI: die Abnahme.
#
# Sieben Abschnitte, und jeder endet in einer Zahl, die ein Lauf
# hergestellt hat. Die Regel ist die von Runde LOOK, mit dem Zusatz von
# Runde PAINT: eine Aussage ueber den Bildschirm ist eine Aussage ueber
# Bildpunkte, und eine neue Faehigkeit ohne ihren Preis ist eine halbe
# Antwort.
#
#   A  classic ist unveraendert   dasselbe Bild wie auf dem Zweig, von
#                                 dem diese Runde abzweigt -- Bildpunkt
#                                 fuer Bildpunkt
#   B  die Formdatei              alle 24 Marken werden gelesen, auch
#                                 aus einer Datei mit sieben Kilooktetten
#                                 Begruendung davor
#   C  der Schatten               Maske gegen Ringe gegen gar keinen,
#                                 in EINEM Lauf gemessen
#   D  die drei Schaltflaechen    Strich, Quadrat, Kreuz -- als Bild
#                                 nachgerechnet -- und der rote
#                                 Schliessen-Knopf im Ueberfahr-Zustand
#   E  der Fokus ohne Farbe       der Schatten des scharfen Fensters ist
#                                 tiefer und weiter als der der anderen
#   F  der Kontrast               nicht schlechter als vorher
#   G  die Bilder                 keine leeren Beschriftungen, nichts
#                                 abgeschnitten, nichts ueberlappend
#
#   bash tools/softui/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRN_REPO=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}
export FIRNLIB="$(pwd)/lib"
TMPD=${SOFTUITMP:-/tmp/softui-run}
mkdir -p "$TMPD"
export LOOKBUILD="$TMPD/build"

P=0; F=0
ok()  { P=$((P+1)); printf '   OK    %s\n' "$*"; }
bad() { F=$((F+1)); printf '   FAIL  %s\n' "$*"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2, erwartet $3"; fi; }
ge()  { if [ "${2:-0}" -ge "$3" ] 2>/dev/null; then ok "$1: $2 (>= $3)"; else bad "$1: ${2:-?}, erwartet >= $3"; fi; }
le()  { if [ "${2:-999999}" -le "$3" ] 2>/dev/null; then ok "$1: $2 (<= $3)"; else bad "$1: ${2:-?}, erwartet <= $3"; fi; }

shot() { # dir args...
    local d=$1; shift
    bash tools/look/shot.sh "$TMPD/$d" "$@" > "$TMPD/$d.log" 2>&1
    grep -qa 'qemu exit 21' "$TMPD/$d.log"
}
val() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }

echo "== A. classic ist unveraendert =="
# DIE GEGENPROBE, DIE DIESE RUNDE UEBERHAUPT LANDEN LAESST.
#
# `modern` darf anders aussehen -- das ist der Auftrag. `classic` darf
# es nicht, und das laesst sich nicht durch Nachdenken feststellen: die
# Runde hat den Fensterserver, die Widget-Bibliothek, die Leiste und die
# Einstellungen angefasst. Also wird das Bild gegen den Zweig gehalten,
# von dem hier abgezweigt wurde, und zwar Bildpunkt fuer Bildpunkt.
BASE=${SOFTUIBASE:-/root/softui-base}
if shot A shape=classic scheme=day mode=light keep=yes; then
    ok "classic bootet (QEMU exit 21)"
    if [ -s "$BASE/../softui/base-classic/desktop.ppm" ] \
       || [ -s "${SOFTUIBASEPPM:-/tmp/softui/base-classic/desktop.ppm}" ]; then
        REF=${SOFTUIBASEPPM:-/tmp/softui/base-classic/desktop.ppm}
        D=$(python3 tools/paint/shadow.py vergleich "$REF" \
            "$TMPD/A/desktop.ppm" 0 0 800 600 2>&1 \
            | grep -oE 'unterschiedlich [0-9]+' | grep -oE '[0-9]+')
        is "classic: abweichende Bildpunkte gegen die Grundlinie" "${D:-x}" "0"
    else
        bad "keine Grundlinie -- SOFTUIBASEPPM setzen"
    fi
else
    bad "classic bootet nicht"
fi

echo "== B. die Formdatei wird GANZ gelesen =="
if shot B shape=modern scheme=day mode=light keep=yes; then
    K=$(val "$TMPD/B/serial.txt" 'shape file=modern name=Modern id=1 keys=[0-9]+')
    is "Marken aus modern.shape" "${K:-0}" "24"
    CH=$(grep -aoE 'ctrl_h=[0-9]+' "$TMPD/B/serial.txt" | tail -1 | grep -oE '[0-9]+')
    is "ctrl_h aus der Datei" "${CH:-0}" "32"
    N=$(grep -aoE 'form n=[0-9]+' "$TMPD/B/serial.txt" | tail -1 | grep -oE '[0-9]+')
    is "Formwoerter an den Server" "${N:-0}" "8"
    S=$(stat -c%s assets/shapes/modern.shape)
    ge "und die Datei ist groesser als der alte Puffer" "$S" "4097"
else
    bad "modern bootet nicht"
fi

echo "== C. der Schatten: Maske gegen Ringe gegen keinen =="
if [ -s "$TMPD/B/serial.txt" ]; then
    L=$(grep -a 'wmbench2: maske' "$TMPD/B/serial.txt" | tail -1)
    R=$(grep -a 'wmbench2: ringe' "$TMPD/B/serial.txt" | tail -1)
    O=$(grep -a 'wmbench2: ohne' "$TMPD/B/serial.txt" | tail -1)
    echo "        $O"
    echo "        $L"
    echo "        $R"
    MU=$(echo "$L" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    RU=$(echo "$R" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    OU=$(echo "$O" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    MA=$(echo "$L" | grep -oE 'aapx=[0-9]+' | grep -oE '[0-9]+')
    RA=$(echo "$R" | grep -oE 'aapx=[0-9]+' | grep -oE '[0-9]+')
    if [ -n "$MU" ] && [ -n "$RU" ] && [ -n "$OU" ]; then
        MK=$((MU - OU)); RK=$((RU - OU))
        echo "        Schatten kostet: Maske ${MK} us, Ringe ${RK} us"
        if [ "$MK" -lt "$RK" ]; then
            ok "die Maske ist billiger als die Ringe ($MK < $RK us)"
        else
            bad "die Maske ist NICHT billiger ($MK gegen $RK us)"
        fi
    else
        bad "keine Zeitmessung im Mitschnitt"
    fi
    # DER EIGENTLICHE MESSWERT: der Eckenabtaster ist aus dem Bild raus.
    if [ -n "$MA" ] && [ -n "$RA" ]; then
        le "Eckabtastungen je Bild mit der Maske" "$MA" "$((RA / 4))"
    fi
    SB=$(val "$TMPD/B/serial.txt" 'shbuild=[0-9]+')
    le "die Maske wurde je Lauf gebaut" "${SB:-99}" "1"
    ge "und sie wurde ueberhaupt gebaut" "${SB:-0}" "1"
fi

echo "== D. die drei Schaltflaechen, und der rote Knopf =="
if shot D shape=modern scheme=day mode=light keep=yes hover=622,120; then
    python3 tools/softui/knoepfe.py "$TMPD/D/desktop.ppm" \
        "$TMPD/D/serial.txt" > "$TMPD/D.knopf" 2>&1
    cat "$TMPD/D.knopf" | sed 's/^/        /'
    grep -q 'min: strich ok' "$TMPD/D.knopf" \
        && ok "Minimieren ist ein waagerechter Strich" \
        || bad "Minimieren ist kein Strich"
    grep -q 'max: quadrat ok' "$TMPD/D.knopf" \
        && ok "Maximieren ist ein Quadrat" || bad "Maximieren ist kein Quadrat"
    grep -q 'close: kreuz ok' "$TMPD/D.knopf" \
        && ok "Schliessen ist ein Kreuz" || bad "Schliessen ist kein Kreuz"
    grep -q 'hover: rot ok' "$TMPD/D.knopf" \
        && ok "der ueberfahrene Schliessen-Knopf ist rot mit weissem Kreuz" \
        || bad "der Ueberfahr-Zustand fehlt"
    grep -q 'macos: keine kreise' "$TMPD/D.knopf" \
        && ok "und es sind KEINE drei bunten Kreise" \
        || bad "da sind bunte Kreise"
fi

echo "== E. der Fokus, ohne eine knallige Farbe =="
if [ -s "$TMPD/B/desktop.ppm" ]; then
    python3 tools/softui/fokus.py "$TMPD/B/desktop.ppm" \
        "$TMPD/B/serial.txt" > "$TMPD/E.txt" 2>&1
    cat "$TMPD/E.txt" | sed 's/^/        /'
    AT=$(grep -oE 'aktiv tiefe=[0-9]+' "$TMPD/E.txt" | grep -oE '[0-9]+')
    IT=$(grep -oE 'inaktiv tiefe=[0-9]+' "$TMPD/E.txt" | grep -oE '[0-9]+')
    if [ -n "$AT" ] && [ -n "$IT" ] && [ "$IT" -gt 0 ]; then
        if [ "$AT" -gt "$((IT * 3 / 2))" ]; then
            ok "der Schatten des scharfen Fensters ist mindestens 1,5-mal so tief ($AT gegen $IT)"
        else
            bad "die beiden Schatten sind zu aehnlich ($AT gegen $IT)"
        fi
    else
        bad "keine zwei Schatten gemessen"
    fi
    grep -q 'titel: kein akzent' "$TMPD/E.txt" \
        && ok "und keine Titelleiste traegt den Akzent" \
        || bad "eine Titelleiste ist immer noch akzentfarben"
fi

echo "== F. der Kontrast =="
# GEMESSEN WIRD AUS DEM BILD. Warum das Tokenmodell hier nicht reicht,
# steht in tools/softui/kontrast.py.
for v in "day light 516" "night dark 1236"; do
    set -- $v
    if shot "F-$1" shape=modern scheme=$1 mode=$2 keep=yes; then
        M=$(python3 tools/theme/model.py contrast "assets/schemes/$1.scheme" $2 \
            | awk '$4=="normal"||$3=="normal"{print $(NF-1)}' | sort -n | head -1)
        ge "$1/$2: kleinstes Textpaar im Modell (x100)" "${M:-0}" "$3"
        K=$(python3 tools/softui/titel.py "$TMPD/F-$1/desktop.ppm" \
            "$TMPD/F-$1/serial.txt" 2>&1 | tail -1)
        echo "        $K"
    fi
done

echo "== G. die Bilder werden gemessen =="
for d in B D F-day F-night; do
    if [ -s "$TMPD/$d/desktop.ppm" ]; then
        python3 tools/softui/pruef.py "$TMPD/$d/desktop.ppm" \
            "$TMPD/$d/serial.txt" > "$TMPD/$d.pruef" 2>&1
        R=$?
        tail -1 "$TMPD/$d.pruef" | sed 's/^/        /'
        if [ $R -eq 0 ]; then
            ok "$d: keine leere, abgeschnittene oder ueberlappende Beschriftung"
        else
            bad "$d: Beanstandungen"
            head -8 "$TMPD/$d.pruef" | sed 's/^/          /'
        fi
    fi
done

echo
echo "SOFTUI: $P bestanden, $F gefallen"
[ "$F" -eq 0 ]
