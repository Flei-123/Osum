#!/usr/bin/env bash
# tools/check-ui.sh -- DIE REGEL: BEDIENELEMENTE KOMMEN AUS DER BIBLIOTHEK.
#
# Justins Vorgabe, 11.09.2026:
#   "Ich will nicht, dass jemand es selber hartkodiert oder eine eigene
#    Library verwendet, das ergibt nur Chaos. Wenn es einen Bug gibt,
#    brauchen wir nur einmal die Lib aendern."
#
# Diese Pruefung faellt aus, wenn ein Programm ausserhalb der
# Bibliotheksschicht wieder anfaengt, ein Bedienelement SELBST zu malen.
#
#   tools/check-ui.sh          pruefen
#   tools/check-ui.sh --liste  zusaetzlich zeigen, wer was benutzt
#
# ================================================== WAS GEMESSEN WIRD
#
# Roh gemalt wird mit den Primitiven aus `wlibc`: rect, hline, vline,
# frame, frame3, px. Wer die AUSSERHALB der Bibliothek aufruft, malt
# sich sein Element selbst -- genau das soll nicht passieren.
#
# ERLAUBT sind dabei genau zwei Sorten Datei, und beide mit Grund:
#
#   kernel/user/wlib.fi   IST die Bibliothek. Sie MUSS roh malen --
#                         irgendwo muessen die Pixel ja herkommen.
#   kernel/user/icont.fi  ist der Symbol-Pruefstand: er malt Symbole
#                         Pixel fuer Pixel und VERGLEICHT sie. Er baut
#                         kein Bedienelement, er misst eines.
#
# Diese Liste ist bewusst kurz und steht hier im Klartext. Wer einen
# Namen hinzufuegt, muss danebenschreiben WARUM -- sonst ist die Regel
# nach drei Runden wieder weich.
set -u
cd "$(dirname "$0")/.."

# Die Dateien, die roh malen duerfen (siehe Begruendung oben).
ERLAUBT="kernel/user/wlib.fi kernel/user/icont.fi"

# Die rohen Mal-Primitive.
ROH='wlibc\.(rect|hline|vline|frame|frame3|px)\('

fehler=0
treffer=""

for f in kernel/user/*.fi; do
    ok=0
    for e in $ERLAUBT; do
        [[ $f == "$e" ]] && ok=1
    done
    [[ $ok == 1 ]] && continue

    # -a: einige Dateien im Baum enthalten eingebettete Binaerdaten
    # (Schriftbilder), grep haelt sie sonst fuer Binaerdateien und
    # sagt nur "binary file matches" -- dann faende diese Pruefung
    # nichts und waere still gruen. Das ist genau die Sorte stiller
    # Fehlschlag, gegen die sie geschrieben ist.
    n=$(grep -acE "$ROH" "$f" 2>/dev/null || true)
    if [[ ${n:-0} -gt 0 ]]; then
        fehler=$((fehler + 1))
        treffer+="  $f: $n rohe Mal-Aufrufe"$'\n'
        if [[ ${1:-} == --liste ]]; then
            grep -anE "$ROH" "$f" | head -10 | sed 's/^/      /'
        fi
    fi
done

echo "== BEDIENELEMENTE KOMMEN AUS DER BIBLIOTHEK =="
if [[ $fehler -gt 0 ]]; then
    echo
    echo "FEHLGESCHLAGEN: $fehler Datei(en) malen selbst statt wlib zu benutzen:"
    echo
    printf '%s' "$treffer"
    echo
    echo "Abhilfe: das Element aus kernel/user/wlib.fi benutzen"
    echo "(label, button, check, entry, list, table, tabs, choice, tile,"
    echo " card, slider, sep, scrollarea, menubar, dlg_*) oder, wenn es"
    echo "das dort wirklich nicht gibt, es DORT einbauen -- nicht hier."
    echo
    echo "Ist eine Datei zu Recht roh (Pruefstand, Bibliothek selbst),"
    echo "gehoert ihr Name mit Begruendung in ERLAUBT in diesem Skript."
    exit 1
fi

geprueft=$(ls kernel/user/*.fi | wc -l)
echo "  $geprueft Dateien geprueft, $(echo $ERLAUBT | wc -w) begruendete Ausnahmen"
echo "  0 Programme malen sich ein Bedienelement selbst  OK"
echo
echo "CHECK-UI PASSED."
