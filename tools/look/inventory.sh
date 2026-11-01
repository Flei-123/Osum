#!/usr/bin/env bash
#
# ====================================================== WARUM ES EXISTIERT
#
# ================================================== WAS GEMESSEN WIRD
#
#   tools/look/inventory.sh
#
set -u
cd "$(dirname "$0")/../.."

ABBILD=tools/usbimg/build.sh
STAND=tools/look/shot.sh

[ -f "$ABBILD" ] || { echo "fehlt: $ABBILD" >&2; exit 2; }
[ -f "$STAND" ]  || { echo "fehlt: $STAND" >&2; exit 2; }

# ------------------------------------------------------------------
# DIE BEGRUENDETEN UNTERSCHIEDE.
#
ONLY_IMAGE="jarvis ssl beispiel"

ONLY_RIG="icons"

fehler=0

etc_von() {
    grep -oP '/etc/\K[a-z]+(?=/)' "$1" | sort -u
}
a_etc=$(etc_von "$ABBILD")
s_etc=$(etc_von "$STAND")

echo "== /etc IN THE IMAGE AND IN THE TEST BENCH =="
fehlt=""
for d in $a_etc; do
    if ! echo "$s_etc" | grep -qx "$d"; then
        ist_ausnahme=0
        for e in $ONLY_IMAGE; do [ "$d" = "$e" ] && ist_ausnahme=1; done
        if [ $ist_ausnahme = 0 ]; then
            fehlt+="  /etc/$d -- im Abbild, NICHT im Pruefstand"$'\n'
            fehler=$((fehler + 1))
        fi
    fi
done
if [ -n "$fehlt" ]; then
    printf '%s' "$fehlt"
else
    echo "  equal (except the $(echo $ONLY_IMAGE | wc -w) justified exceptions)"
fi

quellen_von() {
    grep -oP '=\K(assets|locale)/[A-Za-z0-9/._-]+' "$1" | sort -u
    grep -oP 'for [a-z_]+ in \K(assets|locale)/[A-Za-z0-9/._*-]+' "$1" \
        | sed 's|/\*.*||' | sort -u
}
a_q=$(quellen_von "$ABBILD")
s_q=$(quellen_von "$STAND")

echo
echo "== SOURCES FROM assets/ AND locale/ =="
fehlt2=""
for q in $a_q; do
    if ! echo "$s_q" | grep -qx "$q"; then
        base=$(basename "$q")
        ist_ausnahme=0
        for e in $ONLY_IMAGE $ONLY_RIG; do
            case "$q" in *"$e"*) ist_ausnahme=1 ;; esac
        done
        if [ $ist_ausnahme = 0 ]; then
            fehlt2+="  $q -- im Abbild, NICHT im Pruefstand"$'\n'
            fehler=$((fehler + 1))
        fi
    fi
done
if [ -n "$fehlt2" ]; then
    printf '%s' "$fehlt2"
else
    echo "  equal (except the justified exceptions)"
fi

echo
echo "== SYMBOLS (netview): COUNT, NOT ONLY PRESENCE =="
symbole_von() {
    sed 's/#.*//' "$1" \
        | grep -oP 'state-[a-z]+|mark-[a-z]+|sys-[a-z]+|tile-[a-z]+' \
        | sort -u
}
a_n=$(symbole_von "$ABBILD" | wc -l)
s_n=$(symbole_von "$STAND" | wc -l)
if [ "${a_n:-0}" -eq 0 ] && [ "${s_n:-0}" -eq 0 ]; then
    a_n=$(ls assets/netview/ 2>/dev/null | wc -l)
    s_n=$a_n
    echo "  both scripts build the list at run time; in the tree: $a_n files"
else
    echo "  Abbild $a_n, Pruefstand $s_n"
    if [ "$a_n" != "$s_n" ]; then
        echo "  DIFFERENT -- exactly the bug from round ECHT-2"
        echo "  only in the image:"
        comm -23 <(symbole_von "$ABBILD") <(symbole_von "$STAND") \
            | sed 's/^/    /'
        fehler=$((fehler + 1))
    fi
fi

echo
echo "== THE BRAND: IS THE GENERATED IMAGE CURRENT? =="
GEN=kernel/user/brand_start.fi
if [ ! -f "$GEN" ]; then
    echo "  $GEN fehlt"
    fehler=$((fehler + 1))
elif [ ! -d assets/marke ]; then
    echo "  assets/marke fehlt"
    fehler=$((fehler + 1))
else
    neuer=""
    for png in assets/marke/start-*.png; do
        [ -e "$png" ] || continue
        [ "$png" -nt "$GEN" ] && neuer+=" $(basename "$png")"
    done
    if [ -n "$neuer" ]; then
        echo "  NEWER THAN THE GENERATED IMAGE:$neuer"
        echo "  -> python3 tools/brand/startimage.py assets/marke $GEN"
        fehler=$((fehler + 1))
    else
        groessen=$(grep -oP '^\s+if wunsch >= \K[0-9]+' "$GEN" | tr '\n' ' ')
        dateien=$(ls assets/marke/start-*.png 2>/dev/null \
            | grep -oP 'start-\K[0-9]+' | sort -n | tr '\n' ' ')
        echo "  eingebackene Groessen: $groessen"
        echo "  Dateien in assets/marke: $dateien"
        echo "  marke_start.fi is current"
    fi
fi

echo
if [ $fehler -gt 0 ]; then
    echo "BESTUECKUNG FEHLGESCHLAGEN ($fehler Befund(e))."
    echo
    echo "The test bench then measures something other than what the user boots --"
    echo "and a screenshot does not say that a file is missing. It"
    echo "shows a replacement glyph, and that looks intentional."
    echo
    echo "Remedy: add the file to tools/look/shot.sh, or -- if"
    echo "it is rightly missing there -- with a JUSTIFICATION in ONLY_IMAGE or"
    echo "ONLY_RIG in this script."
    exit 1
fi
echo "BESTUECKUNG PASSED."
