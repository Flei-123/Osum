#!/usr/bin/env bash
# tools/check-ui.sh -- DIE REGEL: BEDIENELEMENTE KOMMEN AUS DER BIBLIOTHEK,
# UND DIE BIBLIOTHEK MALT SIE MIT fUi.
#
# Justins Vorgabe, 11.09.2026:
#   "Ich will nicht, dass jemand es selber hartkodiert oder eine eigene
#    Library verwendet, das ergibt nur Chaos. Wenn es einen Bug gibt,
#    brauchen wir nur einmal die Lib aendern."
#
# Diese Pruefung faellt aus, wenn jemand diese Regel unterlaeuft -- und
# es gibt DREI Wege, das zu tun. Bis Runde 31 prueste sie nur den
# ersten.
#
#   tools/check-ui.sh          pruefen
#   tools/check-ui.sh --liste  zusaetzlich zeigen, wer was benutzt
#
# ================================================== WAS GEMESSEN WIRD
#
# 1. EIN PROGRAMM MALT SICH SEIN ELEMENT SELBST.
#
#    Roh gemalt wird mit den Primitiven aus `wlibc`. Die Liste war bis
#    Runde 31 sechs Namen lang (rect, hline, vline, frame, frame3, px)
#    und damit zu kurz: `rrect`, `rframe`, `rring`, `vrect`, `vkreis`,
#    `divider` und `drop_shadow` malen genauso eine Flaeche, und wer
#    einen Knopf aus `rrect` + `rring` zusammensetzt, hat ihn
#    selbstgemalt. Jetzt stehen alle darin.
#
# 2. NEU (Runde 31): EINE ZWEITE UMSETZUNG NEBEN fUi.
#
#    Seit Runde 31 malt die Bibliothek ihre Flaechen mit fUi
#    (kernel/user/fuib.fi -> lib/fui, ueber vendor/firn/COMMIT in jedem
#    Baum derselbe). Wer in wlib.fi eine NEUE `paint_*`- oder
#    `mal_*`-Funktion anlegt, die ihre Flaeche selbst aus wlibc-
#    Primitiven baut, OHNE vorher die Bruecke zu fragen, stellt genau
#    die zweite Umsetzung daneben, die der Auftrag verbietet -- ein
#    Fehler muesste dann an zwei Stellen behoben werden.
#
#    Gepruefte Bedingung: jede Funktion in wlib.fi, die ein rohes
#    Primitiv benutzt, muss in ihrem Rumpf auch `fuib.` aufrufen. Der
#    Rueckfall auf das rohe Malen bleibt erlaubt (und ist gewollt: ohne
#    Fensterflaeche kann fUi nicht malen, und ein Element, das dann gar
#    nicht erscheint, waere schlimmer als ein eckiges) -- er muss nur
#    HINTER der Bruecke stehen und nicht an ihrer Stelle.
#
# 3. NEU (Runde 31): EINE EIGENE OBERFLAECHENBIBLIOTHEK.
#
#    Wer `import fui.*` direkt in ein Programm schreibt, umgeht die
#    Bibliothek und baut sich seine eigene Oberflaeche daneben. fUi
#    gehoert hinter wlib, nicht neben es. Erlaubt ist es genau dort, wo
#    die Naht sitzt (fuib.fi) und in den Pruefstaenden.
#
# ================================================== DIE AUSNAHMEN
#
# Sie stehen hier im Klartext, und wer einen Namen hinzufuegt, muss
# danebenschreiben WARUM -- sonst ist die Regel nach drei Runden wieder
# weich.
set -u
cd "$(dirname "$0")/.."

# Die Dateien, die roh malen duerfen.
#   wlib.fi   IST die Bibliothek. Sie muss roh malen koennen --
#             irgendwo muessen die Bildpunkte herkommen, und sie haelt
#             den Rueckfall fuer den Fall ohne Fensterflaeche.
#   icont.fi  ist der Symbol-Pruefstand: er malt Symbole Punkt fuer
#             Punkt und VERGLEICHT sie. Er baut kein Bedienelement, er
#             misst eines.
#   fuib.fi   ist die Naht zu fUi. Sie malt selbst nichts roh, darf aber
#             die Flaeche des Servers anfassen.
ERLAUBT_ROH="kernel/user/wlib.fi kernel/user/icont.fi kernel/user/fuib.fi"

# Die Dateien, die fUi direkt anfassen duerfen.
#   fuib.fi   ist die Naht -- genau ihre Aufgabe.
ERLAUBT_FUI="kernel/user/fuib.fi"

# Die rohen Mal-Primitive. VOLLSTAENDIG -- siehe Punkt 1 oben.
ROH='wlibc\.(rect|hline|vline|frame|frame3|px|rrect|rframe|rring|vrect|vkreis|divider|drop_shadow)\('

fehler=0
treffer=""

# ---------------------------------------------------------------- 1.
for f in kernel/user/*.fi; do
    ok=0
    for e in $ERLAUBT_ROH; do
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
        treffer+="  $f: $n rohe Mal-Aufrufe (malt sich sein Element selbst)"$'\n'
        if [[ ${1:-} == --liste ]]; then
            grep -anE "$ROH" "$f" | head -10 | sed 's/^/      /'
        fi
    fi
done

# ---------------------------------------------------------------- 3.
for f in kernel/user/*.fi; do
    ok=0
    for e in $ERLAUBT_FUI; do
        [[ $f == "$e" ]] && ok=1
    done
    [[ $ok == 1 ]] && continue
    n=$(grep -acE '^import fui\.' "$f" 2>/dev/null || true)
    if [[ ${n:-0} -gt 0 ]]; then
        fehler=$((fehler + 1))
        treffer+="  $f: greift direkt auf fUi zu (eigene Oberflaeche daneben)"$'\n'
    fi
done

# ---------------------------------------------------------------- 2.
# Jede Funktion in wlib.fi, die roh malt, muss die Bruecke fragen.
# Awk teilt die Datei an den `fn `-Zeilen und sieht in jedem Rumpf nach.
zweite=$(awk '
/^fn /   { if (name != "" && roh > 0 && br == 0) print "  " name;
           name = $2; sub(/\(.*/, "", name); roh = 0; br = 0; next }
/wlibc\.(rect|hline|vline|frame|frame3|px|rrect|rframe|rring|vrect|vkreis|divider|drop_shadow)\(/ { roh++ }
/fuib\./ { br++ }
END      { if (name != "" && roh > 0 && br == 0) print "  " name }
' kernel/user/wlib.fi)

# DIE BEGRUENDETEN AUSNAHMEN INNERHALB DER BIBLIOTHEK.
#
# Diese Funktionen malen roh und fragen die Bruecke NICHT -- jede mit
# Grund, und der Grund steht hier und nicht nur im Quelltext:
#
#   focus_ring      fragt sie doch, ueber fuib.ring -- awk sieht es,
#                   die Zeile steht im Rumpf. (Kein Eintrag noetig.)
#   paint_bg        malt den HINTERGRUND eines Fensters, kein Element.
#   paint_leinwand  uebergibt dem Aufrufer seine eigenen Bildpunkte
#                   (Certus malt seine Seite selbst) -- da ist nichts
#                   zu gestalten.
#   paint_kurve     eine Messreihe als Linienzug: sechzig Zahlen mit
#                   `hline`. Ein Diagramm ist kein Bedienelement, und
#                   fUi hat dafuer kein Element.
#   mal_punkt       EIN Bildpunkt, fuer das gerechnete Hintergrundbild
#                   des Schreibtisches.
#   mal_trenner     `wlibc.divider` traegt die Deckkraft aus der
#                   Formentabelle des Systems; fUis Trenner kennt sie
#                   nicht.
#   mal_symbol      die Symbolschrift des Systems (icon_at), nicht eine
#                   Flaeche.
#   say_rects       schreibt nur Zahlen auf die serielle Leitung.
#   paint_sep       `wlibc.divider` traegt die Deckkraft aus der
#                   Formentabelle des Systems (sep_strength); fUis
#                   Trenner kennt sie nicht, und eine Linie mit anderer
#                   Deckkraft waere eine andere Linie.
#   mal_kante3      die zwei Kanten des klassischen Erscheinungsbilds
#                   (hell oben, dunkel unten) -- das ist `classic`, und
#                   fUi malt flach.
#   mal_rahmen      ein Rahmen OHNE Fuellung in wlibs Rollen; er sitzt
#                   um fremde Flaechen (Leinwand, Vorschau) und darf
#                   nichts ausmalen.
#   mal_linie       eine gerade Linie fuer die Graphen des
#                   Aufgabenverwalters.
#   paint_scroll    die Rollleiste rechnet ihren Schieber aus drei
#                   Zahlen des Aufrufers; sie geht ueber mal_tafel,
#                   sobald sie auf fUis Scrollbar umgestellt ist --
#                   Runde 32.
#   paint_graph     ein Verlaufsdiagramm: sechzig Zahlen. Kein
#                   Bedienelement, fUi hat dafuer kein Element.
#   paint_bild      die Bildflaeche des Bildbetrachters: die
#                   Bildpunkte gehoeren dem Bild, nicht der Gestaltung.
#   bild_malen      dasselbe, der innere Teil davon.
#   paint_list, paint_table, paint_tabs, paint_menubar, paint_choice,
#   paint_menu, paint_tile
#                   NOCH NICHT UMGESTELLT. Sie malen ihre Flaechen
#                   weiter selbst; fUi hat die Elemente dafuer
#                   (draw_list, draw_table, draw_tabbar, draw_menubar,
#                   draw_dropdown, draw_menu), aber sie tragen in wlib
#                   Zustaende, die erst uebersetzt werden muessen
#                   (Auswahl, Rollversatz, Spaltenbreiten,
#                   Mehrfachauswahl). Das ist Runde 32 -- hier stehen
#                   sie, damit die Pruefung GRUEN ist und die Liste
#                   trotzdem ehrlich sagt, was offen ist.
# RUNDE 32: DIE KATEGORIE "NOCH NICHT" IST LEER.
#
# paint_list, paint_table, paint_tabs, paint_menubar, paint_choice,
# paint_menu, paint_tile und paint_scroll sind umgestellt -- jede
# einzeln, weil an ihnen Zustaende haengen (Auswahl, Mehrfachauswahl,
# Rollversatz, Spaltenbreiten), die WEITER von wlib gerechnet werden.
# Umgestellt ist, WER die Rechtecke malt, nicht wer den Zustand fuehrt.
# Das ist der Grund, warum fUis eigene draw_list/draw_table NICHT
# benutzt werden: sie bringen ihr eigenes Modell mit, und zwei Modelle
# gegeneinander zu uebersetzen ist der halb uebersetzte Zustand, der
# falsch malt, ohne es zu sagen.
#
# Was hier stehen bleibt, wird NIE fUi, und jedes mit Grund:
#
#   paint_bg        der HINTERGRUND eines Fensters, kein Element.
#   paint_leinwand  die Bildpunkte gehoeren dem Aufrufer (Certus malt
#                   seine Seite selbst) -- da ist nichts zu gestalten.
#   paint_kurve     ein Linienzug aus sechzig Messwerten, mit `hline`.
#   paint_graph     der Rahmen dazu; ein Diagramm ist kein
#                   Bedienelement, und fUi hat dafuer kein Element.
#   mal_linie       die gerade Linie fuer genau diese Graphen.
#   paint_bild      die Bildflaeche des Bildbetrachters -- die
#   bild_malen      Bildpunkte gehoeren dem Bild, nicht der Gestaltung.
#   mal_punkt       EIN Bildpunkt, fuer das gerechnete Hintergrundbild.
#   mal_trenner     `wlibc.divider` traegt die Deckkraft aus der
#   paint_sep       Formentabelle (sep_strength); fUis Trenner kennt
#                   sie nicht, und eine andere Deckkraft ist eine
#                   andere Linie.
#   mal_symbol      die Symbolschrift des Systems (icon_at).
#   mal_kante3      die zwei Kanten des klassischen Erscheinungsbilds
#                   (hell oben, dunkel unten). Das IST `classic`, und
#                   fUi malt flach.
#   mal_rahmen      ein Rahmen OHNE Fuellung, um FREMDE Flaechen
#                   (Leinwand, Vorschau) -- er darf nichts ausmalen.
#   say_rects       schreibt nur Zahlen auf die serielle Leitung.
AUSNAHMEN_LIB="paint_bg paint_leinwand paint_kurve paint_graph mal_linie paint_bild bild_malen mal_punkt mal_trenner paint_sep mal_symbol mal_kante3 mal_rahmen say_rects"

uebrig=""
while read -r fn; do
    [[ -z ${fn// /} ]] && continue
    nm=${fn// /}
    ist_ausnahme=0
    for a in $AUSNAHMEN_LIB; do
        [[ $nm == "$a" ]] && ist_ausnahme=1
    done
    [[ $ist_ausnahme == 1 ]] && continue
    uebrig+="  $nm"$'\n'
done <<< "$zweite"

if [[ -n ${uebrig//[$'\n' ]/} ]]; then
    fehler=$((fehler + 1))
    treffer+="  kernel/user/wlib.fi: malt an fUi vorbei (zweite Umsetzung):"$'\n'
    treffer+="$uebrig"
fi

echo "== BEDIENELEMENTE KOMMEN AUS DER BIBLIOTHEK, DIE MIT fUi MALT =="
if [[ $fehler -gt 0 ]]; then
    echo
    echo "FEHLGESCHLAGEN: $fehler Befund(e):"
    echo
    printf '%s' "$treffer"
    echo
    echo "Abhilfe:"
    echo "  * Ein PROGRAMM nimmt das Element aus kernel/user/wlib.fi"
    echo "    (label, button, check, entry, list, table, tabs, choice,"
    echo "     tile, card, slider, sep, scrollarea, menubar, dlg_*) oder"
    echo "    die Malschicht (mal_tafel, mal_flaeche, mal_balken)."
    echo "  * Die BIBLIOTHEK laesst fUi malen: fuib.mal / fuib.tafel /"
    echo "    fuib.flaeche / fuib.ring, und das rohe Malen nur als"
    echo "    Rueckfall DAHINTER."
    echo "  * Fehlt das Element in fUi, gehoert es in lib/fui -- dort"
    echo "    haben es alle drei Baeume, weil sie denselben Commit"
    echo "    festnageln (vendor/firn/COMMIT)."
    echo
    echo "Ist eine Datei oder Funktion zu Recht roh (Pruefstand, der"
    echo "Hintergrund eines Fensters, ein Diagramm), gehoert ihr Name mit"
    echo "BEGRUENDUNG in ERLAUBT_ROH bzw. AUSNAHMEN_LIB in diesem Skript."
    exit 1
fi

geprueft=$(ls kernel/user/*.fi | wc -l)
echo "  $geprueft Dateien geprueft"
echo "  0 Programme malen sich ein Bedienelement selbst"
echo "  0 Programme greifen an der Bibliothek vorbei auf fUi zu"
echo "  0 Funktionen in wlib.fi malen an fUi vorbei"
echo "  Ausnahmen: $(echo $ERLAUBT_ROH | wc -w) Dateien, $(echo $AUSNAHMEN_LIB | wc -w) Funktionen -- alle begruendet"
echo
echo "CHECK-UI PASSED."
