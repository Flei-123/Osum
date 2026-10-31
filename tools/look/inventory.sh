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
NUR_ABBILD="jarvis ssl beispiel"

NUR_STAND="icons"

fehler=0

etc_von() {
    grep -oP '/etc/\K[a-z]+(?=/)' "$1" | sort -u
}
a_etc=$(etc_von "$ABBILD")
s_etc=$(etc_von "$STAND")

echo "== /etc IM ABBILD UND IM PRUEFSTAND =="
fehlt=""
for d in $a_etc; do
    if ! echo "$s_etc" | grep -qx "$d"; then
        ist_ausnahme=0
        for e in $NUR_ABBILD; do [ "$d" = "$e" ] && ist_ausnahme=1; done
        if [ $ist_ausnahme = 0 ]; then
            fehlt+="  /etc/$d -- im Abbild, NICHT im Pruefstand"$'\n'
            fehler=$((fehler + 1))
        fi
    fi
done
if [ -n "$fehlt" ]; then
    printf '%s' "$fehlt"
else
    echo "  gleich (ausser den $(echo $NUR_ABBILD | wc -w) begruendeten Ausnahmen)"
fi

quellen_von() {
    grep -oP '=\K(assets|locale)/[A-Za-z0-9/._-]+' "$1" | sort -u
    grep -oP 'for [a-z_]+ in \K(assets|locale)/[A-Za-z0-9/._*-]+' "$1" \
        | sed 's|/\*.*||' | sort -u
}
a_q=$(quellen_von "$ABBILD")
s_q=$(quellen_von "$STAND")

echo
echo "== QUELLEN AUS assets/ UND locale/ =="
fehlt2=""
for q in $a_q; do
    if ! echo "$s_q" | grep -qx "$q"; then
        base=$(basename "$q")
        ist_ausnahme=0
        for e in $NUR_ABBILD $NUR_STAND; do
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
    echo "  gleich (ausser den begruendeten Ausnahmen)"
fi

echo
echo "== SYMBOLE (netview): ANZAHL, NICHT NUR VORHANDENSEIN =="
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
    echo "  beide Skripte bauen die Liste zur Laufzeit; im Baum: $a_n Dateien"
else
    echo "  Abbild $a_n, Pruefstand $s_n"
    if [ "$a_n" != "$s_n" ]; then
        echo "  UNTERSCHIEDLICH -- genau der Fehler aus Runde ECHT-2"
        echo "  nur im Abbild:"
        comm -23 <(symbole_von "$ABBILD") <(symbole_von "$STAND") \
            | sed 's/^/    /'
        fehler=$((fehler + 1))
    fi
fi

echo
echo "== DIE MARKE: IST DAS ERZEUGTE BILD AKTUELL? =="
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
        echo "  NEUER ALS DAS ERZEUGTE BILD:$neuer"
        echo "  -> python3 tools/brand/startimage.py assets/marke $GEN"
        fehler=$((fehler + 1))
    else
        groessen=$(grep -oP '^\s+if wunsch >= \K[0-9]+' "$GEN" | tr '\n' ' ')
        dateien=$(ls assets/marke/start-*.png 2>/dev/null \
            | grep -oP 'start-\K[0-9]+' | sort -n | tr '\n' ' ')
        echo "  eingebackene Groessen: $groessen"
        echo "  Dateien in assets/marke: $dateien"
        echo "  marke_start.fi ist aktuell"
    fi
fi

echo
if [ $fehler -gt 0 ]; then
    echo "BESTUECKUNG FEHLGESCHLAGEN ($fehler Befund(e))."
    echo
    echo "Der Pruefstand misst dann etwas anderes, als der Nutzer bootet --"
    echo "und ein Bildschirmfoto sagt nicht, dass eine Datei fehlt. Es"
    echo "zeigt ein Ersatzzeichen, und das sieht aus wie Absicht."
    echo
    echo "Abhilfe: die Datei in tools/look/shot.sh nachtragen, oder -- wenn"
    echo "sie dort zu Recht fehlt -- mit BEGRUENDUNG in NUR_ABBILD bzw."
    echo "NUR_STAND in diesem Skript."
    exit 1
fi
echo "BESTUECKUNG PASSED."
