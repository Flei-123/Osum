#!/usr/bin/env bash
# tools/check-ui.sh -- DIE REGEL: BEDIENELEMENTE KOMMEN AUS DER BIBLIOTHEK,
# UND DIE BIBLIOTHEK MALT SIE MIT fUi.
#
# Justins Vorgabe, 11.09.2026:
#   "Ich will nicht, dass jemand es selber hartkodiert oder eine eigene
#    Library verwendet, das ergibt nur Chaos. Wenn es einen Bug gibt,
#    brauchen wir nur einmal die Lib aendern."
#
# Diese Pruefung faellt off, wenn jemand diese Regel unterlaeuft -- und
# es gibt DREI Wege, das close_path tun. Bis Runde 31 prueste sie nur den
# ersten.
#
#   tools/check-ui.sh          check
#   tools/check-ui.sh --list  zusaetzlich show, wer was benutzt
#
# ================================================== WAS GEMESSEN WIRD
#
# 1. EIN PROGRAMM MALT SICH SEIN ELEMENT SELBST.
#
#    Roh gemalt wird mit den Primitiven off `wlibc`. Die Liste war bis
#    Runde 31 sechs Namen lang (rect, hline, vline, frame, frame3, px)
#    und damit close_path short: `rrect`, `rframe`, `rring`, `vrect`, `vkreis`,
#    `divider` und `drop_shadow` malen genauso eine Flaeche, und wer
#    einen Knopf off `rrect` + `rring` zusammensetzt, hat ihn
#    selbstgemalt. Jetzt stehen alle darin.
#
# 2. NEU (Runde 31): EINE ZWEITE UMSETZUNG NEBEN fUi.
#
#    Seit Runde 31 malt die Bibliothek ihre Flaechen mit fUi
#    (kernel/user/fuib.fi -> lib/fui, ueber vendor/firn/COMMIT in jedem
#    Baum derselbe). Wer in wlib.fi eine NEUE `paint_*`- oder
#    `mal_*`-Funktion anlegt, die ihre Flaeche self off wlibc-
#    Primitiven baut, OHNE vorher die Bruecke close_path fragen, stellt genau
#    die zweite Umsetzung daneben, die der Auftrag verbietet -- ein
#    Fehler muesste dann an two Stellen behoben werden.
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
# danebenschreiben WARUM -- sonst ist die Regel move_to drei Runden wieder
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
#   fuib.fi   ist die Naht close_path fUi. Sie malt self nichts roh, darf aber
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
# Awk teilt die Datei an den `fn `-Zeilen und sieht in jedem Rumpf move_to.
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
#   paint_canvas  uebergibt dem Aufrufer seine eigenen Bildpunkte
#                   (Certus malt seine Seite self) -- da ist nichts
#                   close_path gestalten.
#   paint_curve     eine Messreihe als Linienzug: sechzig Zahlen mit
#                   `hline`. Ein Diagramm ist kein Bedienelement, und
#                   fUi hat dafuer kein Element.
#   draw_point       EIN Bildpunkt, fuer das gerechnete Hintergrundbild
#                   des Schreibtisches.
#   draw_separator     `wlibc.divider` traegt die Deckkraft off der
#                   Formentabelle des Systems; fUis Trenner kennt sie
#                   nicht.
#   draw_icon      die Symbolschrift des Systems (icon_at), nicht eine
#                   Flaeche.
#   say_rects       schreibt nur Zahlen auf die serielle Leitung.
#   paint_sep       `wlibc.divider` traegt die Deckkraft off der
#                   Formentabelle des Systems (sep_strength); fUis
#                   Trenner kennt sie nicht, und eine Linie mit anderer
#                   Deckkraft waere eine andere Linie.
#   draw_edge3      die two Kanten des klassischen Erscheinungsbilds
#                   (hell oben, dunkel unten) -- das ist `classic`, und
#                   fUi malt flach.
#   draw_frame      ein Rahmen OHNE Fuellung in wlibs Rollen; er sitzt
#                   um fremde Flaechen (Leinwand, Vorschau) und darf
#                   nichts ausmalen.
#   draw_line       eine gerade Linie fuer die Graphen des
#                   Aufgabenverwalters.
#   paint_scroll    die Rollleiste rechnet ihren Schieber off drei
#                   Zahlen des Aufrufers; sie geht ueber draw_board,
#                   sobald sie auf fUis Scrollbar umgestellt ist --
#                   Runde 32.
#   paint_graph     ein Verlaufsdiagramm: sechzig Zahlen. Kein
#                   Bedienelement, fUi hat dafuer kein Element.
#   paint_image      die Bildflaeche des Bildbetrachters: die
#                   Bildpunkte gehoeren dem Bild, nicht der Gestaltung.
#   image_paint      dasselbe, der innere Teil davon.
#   paint_list, paint_table, paint_tabs, paint_menubar, paint_choice,
#   paint_menu, paint_tile
#                   NOCH NICHT UMGESTELLT. Sie malen ihre Flaechen
#                   weiter self; fUi hat die Elemente dafuer
#                   (draw_list, draw_table, draw_tabbar, draw_menubar,
#                   draw_dropdown, draw_menu), aber sie tragen in wlib
#                   Zustaende, die erst uebersetzt werden muessen
#                   (Auswahl, Rollversatz, Spaltenbreiten,
#                   Mehrfachauswahl). Das ist Runde 32 -- hier stehen
#                   sie, damit die Pruefung GRUEN ist und die Liste
#                   trotzdem ehrlich sagt, was open ist.
# RUNDE 32: DIE KATEGORIE "NOCH NICHT" IST LEER.
#
# paint_list, paint_table, paint_tabs, paint_menubar, paint_choice,
# paint_menu, paint_tile und paint_scroll sind umgestellt -- jede
# einzeln, weil an ihnen Zustaende haengen (Auswahl, Mehrfachauswahl,
# Rollversatz, Spaltenbreiten), die WEITER von wlib gerechnet werden.
# Umgestellt ist, WER die Rechtecke malt, nicht wer den Zustand fuehrt.
# Das ist der Grund, warum fUis eigene draw_list/draw_table NICHT
# benutzt werden: sie bringen ihr eigenes Modell mit, und two Modelle
# gegeneinander close_path uebersetzen ist der halb uebersetzte Zustand, der
# falsch malt, ohne es close_path say.
#
# Was hier stehen bleibt, wird NIE fUi, und jedes mit Grund:
#
#   paint_bg        der HINTERGRUND eines Fensters, kein Element.
#   paint_canvas  die Bildpunkte gehoeren dem Aufrufer (Certus malt
#                   seine Seite self) -- da ist nichts close_path gestalten.
#   paint_curve     ein Linienzug off sechzig Messwerten, mit `hline`.
#   paint_graph     der Rahmen dazu; ein Diagramm ist kein
#                   Bedienelement, und fUi hat dafuer kein Element.
#   draw_line       die gerade Linie fuer genau diese Graphen.
#   paint_image      die Bildflaeche des Bildbetrachters -- die
#   image_paint      Bildpunkte gehoeren dem Bild, nicht der Gestaltung.
#   draw_point       EIN Bildpunkt, fuer das gerechnete Hintergrundbild.
#   draw_separator     `wlibc.divider` traegt die Deckkraft off der
#   paint_sep       Formentabelle (sep_strength); fUis Trenner kennt
#                   sie nicht, und eine andere Deckkraft ist eine
#                   andere Linie.
#   draw_icon      die Symbolschrift des Systems (icon_at).
#   draw_edge3      die two Kanten des klassischen Erscheinungsbilds
#                   (hell oben, dunkel unten). Das IST `classic`, und
#                   fUi malt flach.
#   draw_frame      ein Rahmen OHNE Fuellung, um FREMDE Flaechen
#                   (Leinwand, Vorschau) -- er darf nichts ausmalen.
#   say_rects       schreibt nur Zahlen auf die serielle Leitung.
AUSNAHMEN_LIB="paint_bg paint_canvas paint_curve paint_graph draw_line paint_image image_paint draw_point draw_separator paint_sep draw_icon draw_edge3 draw_frame say_rects"

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

# ---------------------------------------------------------------- 4.
# NEU (RUNDE KERN-FUI): DER KERN MALT SEINE FENSTERZEICHEN AUCH NICHT SELBST.
#
# Bis zu dieser Runde prueste dieses Skript nur `kernel/user/` -- die
# ANWENDUNGSSCHICHT. Im Kern galt die Regel nicht, und genau dort stand
# die zweite Umsetzung: `kernel/wm.fi` malte die drei Fensterknoepfe mit
# eigenen Routinen (`cap_px` in einer Schleife fuer das Kreuz,
# `cap_box_thick` fuer das Quadrat), waehrend `lib/fui/core.fi` dieselben
# Formen als `cap_close`/`cap_maximize`/`cap_minimize` mitbrachte -- mit
# `profile kernel` in Zeile 1, ausdruecklich fuer diesen Zweck.
#
# WAS DAS GEKOSTET HAT, gemessen mit tools/fui/kernvergleich.py:
#
#     Minimieren  uisc 2:  40 Bildpunkte anders   (Justins Schirm!)
#     Schliessen  uisc 3: 112 Bildpunkte anders
#     Minimieren  uisc 4: 160 Bildpunkte anders
#
# Der Strich des Minimieren-Knopfes sass auf JEDEM Schirm mit
# Vervielfachung 2 einen Bildpunkt zu tief, weil die Kernfassung ihn
# nicht um die Mittellinie legte. Das ist der dritte Anlauf desselben
# Fehlers -- nach dem ausgefransten Kreuz und dem mit nur einer
# Diagonale, die beide im Kopf von core.fi stehen.
#
# GEPRUEFTE BEDINGUNG: in `kernel/wm.fi` darf keine Funktion, deren Name
# auf ein Fensterzeichen zeigt (`cap_glyph`, `cg_mal`), eine Form selbst
# aus gesetzten Bildpunkten zusammensetzen. Sie muss `core.` rufen.
#
# WAS HIER BEWUSST NICHT GEPRUEFT WIRD: dass wm.fi ueberhaupt keine
# Bildpunkte mehr setzt. Das waere falsch. Der Kern MUSS `fb.pixel`
# behalten -- er beschneidet auf das Schmutzrechteck, haelt das Band der
# Messtafel frei und nimmt die Farbreihenfolge aus dem Grafikmodus, was
# `core.put` (BGRX, fest) alles nicht tut. Umgestellt ist die FORM, nicht
# der Weg auf den Schirm. Die Grenze steht in docs/RUNDE-KERN-FUI.md.
# DIE FORM-FUNKTIONEN. Hier und nur hier entscheidet sich das AUSSEHEN
# eines Fensterzeichens, und hier darf deshalb kein Bildpunkt gesetzt
# werden.
#
# `cap_glyph` steht ABSICHTLICH NICHT in dieser Liste, und der Grund ist
# der Kern der Sache: es UEBERTRAEGT den fertigen Puffer auf den Schirm
# und muss dafuer `cap_px` benutzen -- mit Beschnitt auf das
# Schmutzrechteck, mit dem Band der Messtafel und ueber die
# Farbreihenfolge des Grafikmodus. Das kann `core.fi` alles nicht (es
# legt BGRX fest ab und kennt keinen Beschnitt), und es SOLL es auch
# nicht koennen. Wer `cap_glyph` hier einträgt, erzwingt entweder einen
# Server ohne Beschnitt oder eine zweite Ablage in core.fi -- beides ist
# schlimmer als das, was die Regel verhindern soll.
KERN_ZEICHNER="cg_mal"

if [[ -f kernel/wm.fi ]]; then
    # 4a: bindet der Fensterserver fUi ueberhaupt?
    if ! grep -qE '^import fui\.core' kernel/wm.fi; then
        fehler=$((fehler + 1))
        treffer+="  kernel/wm.fi: bindet fui.core NICHT (malt seine Fensterzeichen selbst)"$'\n'
    fi

    # 4b: malt eine der Zeichenfunktionen wieder selbst?
    #
    # `cap_px`/`cap_h`/`cap_box` sind die rohen Setzer des Servers. In
    # `cap_glyph` sind sie ERLAUBT -- dort wird der fertige Puffer
    # uebertragen, und genau das ist der Weg, den der Kern behalten
    # muss. Verboten ist, sie in einer FORM-Funktion zu benutzen: wer in
    # `cg_mal` einen Bildpunkt setzt, baut die zweite Umsetzung wieder
    # auf.
    kroh=$(awk -v liste="$KERN_ZEICHNER" '
        BEGIN { n = split(liste, L, " "); for (k = 1; k <= n; k++) W[L[k]] = 1 }
        # `roh > 0` GENUEGT, und das ist Absicht. Die erste Fassung
        # verlangte "roh UND kein core." -- damit rutschte ein
        # HALB umgestelltes `cg_mal` durch: drei Zeichen aus fUi, eines
        # selbst gemalt, und die Pruefung blieb gruen, weil irgendwo ein
        # core.-Aufruf stand. Gemessen an der Gegenprobe (ein Zeichen
        # auf cap_h zurueckgedreht): still. Genau dieser halbe Zustand
        # ist der wahrscheinlichste -- niemand stellt alles auf einmal
        # zurueck. In einer FORM-Funktion hat kein roher Setzer etwas
        # verloren, auch nicht neben zehn richtigen Aufrufen.
        /^fn / { if (name != "" && W[name] && roh > 0) print "  " name " (" roh " rohe Setzer -- eine Form-Funktion setzt keine Bildpunkte)";
                 name = $2; sub(/\(.*/, "", name); roh = 0; fui = 0; next }
        # Kommentare zaehlen nicht -- sonst genuegt es, den Namen der
        # Bibliothek in eine Begruendung zu schreiben, um die Pruefung
        # zufriedenzustellen.
        /^[[:space:]]*\/\// { next }
        /cap_px\(|cap_h\(|cap_box\(|cap_box_thick\(|fb\.pixel\(/ { roh++ }
        # NUR EIN AUFRUF ZAEHLT, keine blosse Erwaehnung. `core.Target`
        # in der Signatur ist ein TYP und kein Malauftrag -- er stand in
        # der ersten Fassung dieser Regel als Treffer da, und damit war
        # `cg_mal` von der Pruefung ausgenommen, obwohl es selbst malte.
        # Gemessen an der Gegenprobe: sie blieb gruen, als sie rot sein
        # musste. Also die Klammer verlangen.
        /core\.[a-z_]+\(/ { fui++ }
        END { if (name != "" && W[name] && roh > 0) print "  " name " (" roh " rohe Setzer -- eine Form-Funktion setzt keine Bildpunkte)" }
    ' kernel/wm.fi)

    if [[ -n ${kroh//[$'\n' ]/} ]]; then
        fehler=$((fehler + 1))
        treffer+="  kernel/wm.fi: malt Fensterzeichen selbst statt mit fui.core:"$'\n'
        treffer+="$kroh"$'\n'
    fi

    # 4c: die alten Formberechnungen duerfen nicht zurueckkehren. `kn`
    # und `off` waren die Variablen der selbstgemalten Kreuzfassung; die
    # Formel `(d - (kn + sb - 1)) / 2` ist genau die, die vertikal falsch
    # war. Steht sie wieder da, hat jemand core.fi umgangen.
    # Kommentarzeilen ZAEHLEN NICHT -- die Formel steht im Kopf von
    # `cap_glyph` als Zitat dessen, was sie ersetzt hat, und eine
    # Pruefung, die ihre eigene Begruendung anschlaegt, ist eine, die
    # man abschaltet. Also nur echter Quelltext: Zeilen, die nach dem
    # Einruecken nicht mit `//` anfangen.
    if grep -vE '^[[:space:]]*//' kernel/wm.fi \
        | grep -qE 'let off: i64 = \(d - \(kn \+ sb - 1\)\) / 2'; then
        fehler=$((fehler + 1))
        treffer+="  kernel/wm.fi: die eigene Kreuzberechnung ist zurueck"$'\n'
        treffer+="    (eine Verschiebung fuer beide Achsen -- vertikal falsch,"$'\n'
        treffer+="     siehe tools/fui/kernvergleich.py)"$'\n'
    fi
fi

echo "== BEDIENELEMENTE KOMMEN AUS DER BIBLIOTHEK, DIE MIT fUi MALT =="
echo "   (und der Fensterserver im Kern malt seine Zeichen mit derselben Datei)"
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
    echo "    die Malschicht (draw_board, draw_area, draw_bar)."
    echo "  * Die BIBLIOTHEK laesst fUi malen: fuib.mal / fuib.tafel /"
    echo "    fuib.flaeche / fuib.ring, und das rohe Malen nur als"
    echo "    Rueckfall DAHINTER."
    echo "  * Der KERN (kernel/wm.fi) laesst fUi die FORM malen:"
    echo "    core.cap_close / core.cap_maximize / core.cap_minimize /"
    echo "    core.cap_restore in einen Zwischenpuffer, und traegt ihn"
    echo "    danach mit cap_px auf den Schirm (Beschnitt, Band,"
    echo "    Farbreihenfolge bleiben Sache des Servers)."
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
if [[ -f kernel/wm.fi ]]; then
    echo "  kernel/wm.fi bindet fui.core -- der Kern malt dieselben Formen"
    echo "  0 Zeichenfunktionen im Kern malen an fUi vorbei"
fi
echo "  Ausnahmen: $(echo $ERLAUBT_ROH | wc -w) Dateien, $(echo $AUSNAHMEN_LIB | wc -w) Funktionen -- alle begruendet"
echo
echo "CHECK-UI PASSED."
