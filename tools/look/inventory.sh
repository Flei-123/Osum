#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/look/inventory.sh -- IST DER PRUEFSTAND SO BESTUECKT WIE DAS
# ABBILD?
#
# ====================================================== WARUM ES EXISTIERT
#
# Justin, 12.09.2026: "Diesen Fehler hatten wir jetzt dreimal; er darf
# nicht ein viertes Mal auftreten."
#
# Dreimal derselbe Ablauf, und jedes Mal hat er es gefunden und nicht
# die Pruefung:
#
#   Runde ECHT-2   der Pruefstand kopierte drei statt sechs
#                  Symboldateien -- die Kacheln im Kontrollzentrum
#                  waren im Beleg leer.
#   Runde 31/32    `/etc/themes` fehlte im Pruefstand. Das sind die
#                  fertigen Voreinstellungen; ohne sie liest wlibc
#                  andere Werte als auf der Platte.
#   Runde 32       die Marke im Startknopf -- hier lag es zwar NICHT an
#                  der Bestueckung (die Marke ist in marke_start.fi
#                  eingebacken), aber gesucht wurde zuerst dort, weil
#                  es dreimal vorher daran lag.
#
# Das Muster ist immer dasselbe: die Abnahme misst ein System, das
# anders bestueckt ist als das, welches der Nutzer bootet -- und ein
# Bildschirmfoto sagt nicht, dass eine Datei fehlt. Es zeigt einfach
# ein Ersatzzeichen, und das sieht aus wie eine Design-Entscheidung.
#
# ================================================== WAS GEMESSEN WIRD
#
# Beide Bauskripte sagen mit `/pfad=quelle`, was auf die Platte kommt.
# Dieses Skript liest BEIDE und vergleicht die Verzeichnisse unter
# /etc/ und die Quelldateien unter assets/ und locale/.
#
#   tools/look/inventory.sh
#
# Es ist bewusst eine TEXTPRUEFUNG auf den Skripten und kein Vergleich
# zweier gebauter Platten: es soll laufen, ohne 40 Sekunden zu booten,
# und es soll den Fehler zeigen, BEVOR jemand Belege macht.
set -u
cd "$(dirname "$0")/../.."

ABBILD=tools/usbimg/build.sh
STAND=tools/look/shot.sh

[ -f "$ABBILD" ] || { echo "fehlt: $ABBILD" >&2; exit 2; }
[ -f "$STAND" ]  || { echo "fehlt: $STAND" >&2; exit 2; }

# ------------------------------------------------------------------
# DIE BEGRUENDETEN UNTERSCHIEDE.
#
# Nicht alles, was auf ein Geraet gehoert, gehoert in ein
# Bildschirmfoto. Wer hier etwas hinzufuegt, schreibt den Grund
# daneben -- sonst ist die Pruefung nach drei Runden wieder weich.
#
#   jarvis   /etc/jarvis/rechte.conf ist die Rechteliste des Helfers.
#            Sie gehoert zu einem Geraet mit einem Besitzer, nicht zu
#            einem Foto, und kein Programm im Foto liest sie.
#   ssl      /etc/ssl/roots.pem ist der Wurzelspeicher fuer `fetch`.
#            Im Pruefstand gibt es kein Netz nach draussen.
#   beispiel assets/beispiel/hallo.fi liegt unter /beispiel/ und ist
#            ein Begleittext fuer den Editor, keine Bestueckung der
#            Oberflaeche.
NUR_ABBILD="jarvis ssl beispiel"

# Umgekehrt: was der Pruefstand hat und das Abbild nicht.
#   locale/*/icons  die Symbolnamen je Sprache. Das Abbild baut sie
#                   anders ein (ueber das Buendel), nicht als eigene
#                   Datei -- geprueft in Runde 32.
NUR_STAND="icons"

fehler=0

# ------------------------------------------------------------------ 1.
# Die Verzeichnisse unter /etc/.
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

# ------------------------------------------------------------------ 2.
# Die Quelldateien aus assets/ und locale/.
quellen_von() {
    grep -oP '=\K(assets|locale)/[A-Za-z0-9/._-]+' "$1" | sort -u
    # Die Schleifen ueber Glob-Muster nennen das Verzeichnis, nicht die
    # Datei -- also auch die mitnehmen.
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

# ------------------------------------------------------------------ 3.
# DIE SYMBOLDATEIEN -- der Fehler aus Runde ECHT-2, als Zahl.
#
# Damals kopierte der Pruefstand drei der sechs Dateien. Eine Liste
# haette das nicht gezeigt (das Verzeichnis stand ja drin), also wird
# hier GEZAEHLT.
echo
echo "== SYMBOLE (netview): ANZAHL, NICHT NUR VORHANDENSEIN =="
# Das Abbild fuehrt sie in einer Variablen, der Pruefstand in einer
# `for`-Schleife -- also beide Formen lesen und die NAMEN zaehlen,
# nicht die Zeilen.
# OHNE KOMMENTARZEILEN, und das ist nicht Kosmetik: der erste Anlauf
# dieser Pruefung zaehlte auch die Namen, die in einer BEGRUENDUNG
# stehen. Die Gegenprobe (ein Symbol aus der Liste entfernen) blieb
# deshalb gruen -- der Name stand noch im Kommentar darueber. Eine
# Pruefung, die durch ihre eigene Begruendung getaeuscht wird, ist
# keine. Also: Kommentare weg, dann zaehlen.
symbole_von() {
    sed 's/#.*//' "$1" \
        | grep -oP 'state-[a-z]+|mark-[a-z]+|sys-[a-z]+|tile-[a-z]+' \
        | sort -u
}
a_n=$(symbole_von "$ABBILD" | wc -l)
s_n=$(symbole_von "$STAND" | wc -l)
if [ "${a_n:-0}" -eq 0 ] && [ "${s_n:-0}" -eq 0 ]; then
    # Beide bauen die Liste anders -- dann die Dateien im Baum zaehlen.
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

# ------------------------------------------------------------------ 4.
# DIE MARKE. Sie ist EINGEBACKEN und nicht bestueckt -- aber dann muss
# die erzeugte Datei auch zu den Bildern passen, sonst zeigt der
# Startknopf ein anderes Zeichen als assets/marke sagt.
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
