#!/usr/bin/env bash
#
#
#
#   tools/check-ui.sh          check
#   tools/check-ui.sh --list  zusaetzlich show, wer was benutzt
#
# ================================================== WAS GEMESSEN WIRD
#
#
#
#
#
#
#
#
# ================================================== DIE AUSNAHMEN
#
set -u
cd "$(dirname "$0")/.."

ERLAUBT_ROH="kernel/user/fuiapp/hostui/hostdraw.fi kernel/user/icont.fi kernel/user/fuib.fi"

ERLAUBT_FUI="kernel/user/fuib.fi kernel/user/fuiapp.fi kernel/user/fuiscene.fi kernel/user/fuied.fi kernel/user/lock.fi kernel/user/fuiapp/hostui/hostdraw.fi kernel/user/signin.fi kernel/user/traypop.fi kernel/user/calpop.fi kernel/user/wmd.fi kernel/user/compdiff.fi"

ROH='uitextat\.(rect|hline|vline|frame|frame3|px|rrect|rframe|rring|vrect|vkreis|divider|drop_shadow)\('

fehler=0
treffer=""

# ---------------------------------------------------------------- 1.
for f in kernel/user/*.fi; do
    ok=0
    for e in $ERLAUBT_ROH; do
        [[ $f == "$e" ]] && ok=1
    done
    [[ $ok == 1 ]] && continue

    n=$(grep -acE "$ROH" <(bash tools/structure/srcview.sh "$f") 2>/dev/null || true)
    if [[ ${n:-0} -gt 0 ]]; then
        fehler=$((fehler + 1))
        treffer+="  $f: $n rohe Mal-Aufrufe (malt sich sein Element selbst)"$'\n'
        if [[ ${1:-} == --liste ]]; then
            grep -anE "$ROH" <(bash tools/structure/srcview.sh "$f") | head -10 | sed 's/^/      /'
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
    # r442: the gallery parts (lib/fui/navnum, navkit, cmdbar, region) are LIBRARY code for programs -- sizes, geometry, the command
    # bar's model, r71: pagegrid = integer geometry of a tile grid, no widgets (Store); L-006: traypower = state + tooltip text of the battery item (powerd status), no widgets -- not a second surface; backlum = luminance/text-colour decider (integers, W-WINOPTS S4) shared by the window server, jarvismini and programs, paints nothing; lockidle = the seven idle-lock choices of Settings (seconds table), paints nothing; speaktext/speakwords = the screen reader's text builder (role, state, name to spoken words), no widgets; every other fUi module stays the host's business
    n=$(grep -aE '^import fui\.' <(bash tools/structure/srcview.sh "$f") 2>/dev/null | grep -avE '^import fui\.(navnum|navkit|cmdbar|region|tokens|pagegrid|speaktext|speakwords|traypower|backlum|lockidle)$' | grep -ac . || true)
    if [[ ${n:-0} -gt 0 ]]; then
        fehler=$((fehler + 1))
        treffer+="  $f: greift direkt auf fUi zu (eigene Oberflaeche daneben)"$'\n'
    fi
done

zweite=$(awk '
/^fn /   { if (name != "" && roh > 0 && br == 0) print "  " name;
           name = $2; sub(/\(.*/, "", name); roh = 0; br = 0; next }
/uitextat\.(rect|hline|vline|frame|frame3|px|rrect|rframe|rring|vrect|vkreis|divider|drop_shadow)\(/ { roh++ }
/fuib\./ { br++ }
END      { if (name != "" && roh > 0 && br == 0) print "  " name }
' kernel/user/fuiapp/hostui/hostdraw.fi)

#
#
#
#
#
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
    treffer+="  kernel/user/fuiapp/hostui/hostdraw.fi: malt an fUi vorbei (zweite Umsetzung):"$'\n'
    treffer+="$uebrig"
fi

#
#
#
#     Minimieren  uisc 2:  40 Bildpunkte anders   (Justins Schirm!)
#     Schliessen  uisc 3: 112 Bildpunkte anders
#     Minimieren  uisc 4: 160 Bildpunkte anders
#
#
#
#
KERN_ZEICHNER="cg_mal"

if [[ -f kernel/ui/wm.fi ]]; then
    # 4a: bindet der Fensterserver fUi ueberhaupt?
    if ! grep -qE '^import fui\.core' kernel/ui/wm.fi; then
        fehler=$((fehler + 1))
        treffer+="  kernel/ui/wm.fi: bindet fui.core NICHT (malt seine Fensterzeichen selbst)"$'\n'
    fi

    #
    kroh=$(awk -v liste="$KERN_ZEICHNER" '
        BEGIN { n = split(liste, L, " "); for (k = 1; k <= n; k++) W[L[k]] = 1 }
        /^fn / { if (name != "" && W[name] && roh > 0) print "  " name " (" roh " rohe Setzer -- eine Form-Funktion setzt keine Bildpunkte)";
                 name = $2; sub(/\(.*/, "", name); roh = 0; fui = 0; next }
        /^[[:space:]]*\/\// { next }
        /cap_px\(|cap_h\(|cap_box\(|cap_box_thick\(|fb\.pixel\(/ { roh++ }
        /core\.[a-z_]+\(/ { fui++ }
        END { if (name != "" && W[name] && roh > 0) print "  " name " (" roh " rohe Setzer -- eine Form-Funktion setzt keine Bildpunkte)" }
    ' kernel/ui/wm.fi kernel/ui/wm/wmcaption.fi)

    if [[ -n ${kroh//[$'\n' ]/} ]]; then
        fehler=$((fehler + 1))
        treffer+="  kernel/ui/wm.fi: malt Fensterzeichen selbst statt mit fui.core:"$'\n'
        treffer+="$kroh"$'\n'
    fi

    if grep -vE '^[[:space:]]*//' kernel/ui/wm.fi \
        | grep -qE 'let off: i64 = \(d - \(kn \+ sb - 1\)\) / 2'; then
        fehler=$((fehler + 1))
        treffer+="  kernel/ui/wm.fi: die eigene Kreuzberechnung ist zurueck"$'\n'
        treffer+="    (eine Verschiebung fuer beide Achsen -- vertikal falsch,"$'\n'
        treffer+="     siehe tools/fui/kernvergleich.py)"$'\n'
    fi
fi

echo "== CONTROLS COME FROM THE LIBRARY THAT DRAWS WITH fUi =="
echo "   (and the window server in the kernel draws its glyphs with the same file)"
if [[ $fehler -gt 0 ]]; then
    echo
    echo "FEHLGESCHLAGEN: $fehler Befund(e):"
    echo
    printf '%s' "$treffer"
    echo
    echo "Abhilfe:"
    echo "  * A PROGRAM takes the element from kernel/user/fuiapp/hostui/hostdraw.fi"
    echo "    (label, button, check, entry, list, table, tabs, choice,"
    echo "     tile, card, slider, sep, scrollarea, menubar, dlg_*) oder"
    echo "    die Malschicht (draw_board, draw_area, draw_bar)."
    echo "  * The LIBRARY has fUi draw: fuib.mal / fuib.tafel /"
    echo "    fuib.flaeche / fuib.ring, and raw drawing only as"
    echo "    Rueckfall DAHINTER."
    echo "  * The KERNEL (kernel/ui/wm.fi) has fUi draw the SHAPE:"
    echo "    core.cap_close / core.cap_maximize / core.cap_minimize /"
    echo "    core.cap_restore into an intermediate buffer, and carries it"
    echo "    afterwards with cap_px onto the screen (clip, band,"
    echo "    Farbreihenfolge bleiben Sache des Servers)."
    echo "  * If the element is missing in fUi, it belongs in lib/fui -- there"
    echo "    all three trees have it, because they share the same commit"
    echo "    festnageln (vendor/firn/COMMIT)."
    echo
    echo "If a file or function is rightly raw (test bench, the"
    echo "background of a window, a diagram), its name belongs with"
    echo "BEGRUENDUNG in ERLAUBT_ROH bzw. AUSNAHMEN_LIB in diesem Skript."
    exit 1
fi

geprueft=$(ls kernel/user/*.fi | wc -l)
echo "  $geprueft Dateien geprueft"
echo "  0 programs draw a control themselves"
echo "  0 programs bypass the library and reach into fUi"
echo "  0 Funktionen in hostdraw.fi malen an fUi vorbei"
if [[ -f kernel/ui/wm.fi ]]; then
    echo "  kernel/ui/wm.fi bindet fui.core -- der Kern malt dieselben Formen"
    echo "  0 drawing functions in the kernel draw around fUi"
fi
echo "  Exceptions: $(echo $ERLAUBT_ROH | wc -w) files, $(echo $AUSNAHMEN_LIB | wc -w) functions -- all justified"
echo
echo "CHECK-UI PASSED."
