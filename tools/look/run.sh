#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/look/run.sh -- ROUND LOOK: the acceptance run.
#
# Five sections, one per part of the round, and every one of them boots a
# real image and reads the answer out of the PICTURE or out of a line the
# program printed about itself. Nothing here is judged by eye.
#
#   A  the umlauts       a German desktop, and a word with an umlaut
#                        checked glyph by glyph against a second
#                        rasterisation
#   B  the symbols       the battery and network glyphs, their ink
#                        counted, and the fallback when the font is gone
#   C  the form tokens   the scanner, and a rounded corner read off the
#                        diagonal
#   D  two appearances   classic against modern, and the contrast in both
#   E  the alignment     the x of the start button, left and centred
#
#   bash tools/look/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRN_REPO=${FIRN_REPO:-/root/jarvis/projects/u_DiS4in7esMF1/firn}
export FIRNLIB="$(pwd)/lib"
TMPD=${LOOKTMP:-/tmp/look-run}
mkdir -p "$TMPD"
export LOOKBUILD="$TMPD/build"

P=0; F=0
ok()  { P=$((P+1)); printf '   OK    %s\n' "$*"; }
bad() { F=$((F+1)); printf '   FAIL  %s\n' "$*"; }
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2, expected $3"; fi; }
ge()  { if [ "${2:-0}" -ge "$3" ] 2>/dev/null; then ok "$1: $2 (>= $3)"; else bad "$1: ${2:-?}, expected >= $3"; fi; }
val() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }

shot() { # dir args...
    local d=$1; shift
    bash tools/look/shot.sh "$TMPD/$d" "$@" > "$TMPD/$d.log" 2>&1
    grep -qa 'qemu exit 21' "$TMPD/$d.log"
}

echo "== A. the umlauts: a German desktop, measured =="
if shot A user=- icons=yes lang=de uitrace=yes keep=yes; then
    ok "the image boots to the desktop (QEMU exit 21)"
    S="$TMPD/A/serial.txt"
    LG=$(grep -a 'taskbar: lang=' "$S" | tail -1)
    case "$LG" in
        *"lang=de src=2"*) ok "the language came from /etc/locale.conf: $LG" ;;
        *) bad "the taskbar is not on German from the system default: $LG" ;;
    esac
    K=$(grep -a 'taskbar: lang=' "$S" | tail -1 | grep -oE 'keys=[0-9]+' \
        | grep -oE '[0-9]+')
    ge "keys in the message catalogue" "$K" 140
    grep -qa 't=kein Netz' "$S" && ok "the taskbar says 'kein Netz' and not 'no network'" \
        || bad "the taskbar is still English"
    # THE UMLAUT, PIXEL BY PIXEL.
    #
    # The word is `Ausführen`, the launcher's button, and it is on the
    # DEFAULT desktop -- no extra word on the kernel command line, no
    # page that has to be opened first. That matters: the claim is
    # about what a person sees when the machine comes up.
    #
    # It is also SHORT, and that is deliberate. The reference
    # rasteriser accumulates its advances a fraction of a pixel
    # differently from the kernel's 26.6 fixed point, so over forty
    # characters the two drift by half a pixel and the checker reports
    # a handful of edge pixels as wrong -- a property of the CHECKER,
    # not of the screen. Under about twenty characters there is no
    # drift at all, and a proof should not need a tolerance it can
    # avoid.
    #
    # THE SERIAL LINE IS SHARED BY FIVE PROCESSES and `ulib.say` is not
    # atomic, so a line can come out cut in half by another program's.
    # Take the last COMPLETE one; there are several repaints, so there
    # is one.
    L=$(grep -aoE 'kind=2 x=[0-9]+ base=[0-9]+ fg=[0-9]+ bg=[0-9]+ t=Ausführen' "$S" | tail -1)
    if [ -n "$L" ]; then
        X=$(echo "$L" | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
        B=$(echo "$L" | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
        # The window's inner origin. A window clamped into the screen
        # corner reports its OUTER position, so the inset is the border
        # plus the title bar -- the same 2 and 22 the settings program
        # adds when it opens a drop-down.
        R=$(python3 tools/gfx/checkshot.py ttext "$TMPD/A/desktop.ppm" \
            assets/osum-sans.ttf 15 $((X + 2)) $((B + 22)) \
            15 23 42 255 255 255 "Ausführen" 8 2>&1)
        echo "        $R"
        case "$R" in
            *", 0 falsch"*) ok "'Ausführen' is on the screen, pixel for pixel" ;;
            *) bad "the umlaut word does not match a second rasterisation" ;;
        esac
    else
        bad "the launcher did not report its Run button"
    fi
    N=$(python3 tools/i18n/scan.py 2>/dev/null | grep -aoE '^gefunden: [0-9]+' | grep -oE '[0-9]+')
    is "hardcoded German surface text (tools/i18n/scan.py)" "${N:-x}" "0"
    # THE STRING FROM THE PHOTOGRAPH. The starter's rows are the bundle
    # labels, and the bundle labels never pass through the catalogue --
    # which is why "Text schreiben und aendern" survived round I18N,
    # round LOOK part A and two addenda, in plain sight, three rows
    # under a correctly drawn "Ausführen".
    if python3 tools/look/umlaut.py "$S" "$TMPD/A/desktop.ppm" "Suchen" \
            "Editor  --  Text schreiben und ändern" 0; then
        ok "the bundle label is on the screen with a real 'ä'"
    else
        bad "the editor's description does not match a second rasterisation"
    fi
fi

echo "== A2. five DIFFERENT umlaut characters, pixel for pixel =="
#
# Part A proved one string. One string is not enough: 'ä' and 'ü' are
# all over the catalogue, 'ß' and 'Ö' are rare, and a font cut down to
# 339 characters can have a hole exactly there without "Ausführen" ever
# noticing. So: five characters, four widgets, three windows.
#
# TWO PICTURES AND NOT ONE, and the reason is worth writing down. The
# theme window and the file manager are laid out by the same tiler, and
# it gives the file manager 396 pixels when the starter is up. The
# column "Größe" begins at x=368 and is 44 wide, so it ends 20 pixels
# past its own window -- and what stands there is the NEXT window. That
# is not a font fault and must not be measured as one; `umlaut.py` says
# so instead. Without the starter the manager gets 660 and the string
# fits. Both pictures are of a German desktop; neither is arranged to
# make a test pass.
PROGS_TT="desktop taskbar settings launcher dhcp explorer widgetdemo themetest locate sh echo ls cat edit"
if shot A2a lang=de icons=yes uitrace=yes extra="themegui" progs="$PROGS_TT" keep=yes; then
    if python3 tools/look/umlaut.py "$TMPD/A2a/serial.txt" \
            "$TMPD/A2a/desktop.ppm" "Themenprobe" "Übernehmen" 0; then
        ok "a CAPITAL umlaut is drawn: 'Übernehmen'"
    else
        bad "'Übernehmen' does not match a second rasterisation"
    fi
else
    bad "A2a did not boot"
fi
# A2b HAT ABSICHTLICH KEIN themetest UND KEINEN STARTER, und der Grund
# ist gemessen: sobald DREI Anwendungsfenster offen sind, kachelt der
# Fenstermanager der Runde TILING sie, und der Dateimanager bekommt 396
# Bildpunkte statt der 664, die er anfordert. Seine Spalte "Größe"
# faengt bei x=368 an und ist 44 breit -- sie passt dann nicht mehr ins
# eigene Fenster. Mit zwei Fenstern bleibt die Anordnung frei, das
# Fenster ist 660 breit, und die Zeichenkette steht ganz darin.
if shot A2b lang=de icons=yes uitrace=yes extra="themegui nostart" keep=yes; then
    # TOLERANCE 64, AND HERE IS THE MEASURED NUMBER FOR IT. The two dots
    # of an 'ö' are a second glyph box over the first, and where two
    # boxes overlap the library mixes glyph ON glyph while the reference
    # mixes each onto the clean ground -- the same effect tools/k15
    # documents for the "ff" in "Öffnen". Measured on this line: at
    # tolerance 0 three of 282 ink pixels differ, at 16 one, at 64 none.
    # The largest deviation is therefore under 64 of 255 steps and
    # touches three pixels. Nothing here is loosened: the string, the
    # position and the colours all still have to be right.
    if python3 tools/look/umlaut.py "$TMPD/A2b/serial.txt" \
            "$TMPD/A2b/desktop.ppm" "Datei-Explorer" "Größe" 64; then
        ok "'ö' and 'ß' stand next to each other in the table heading"
    else
        bad "'Größe' does not match a second rasterisation"
    fi
else
    bad "A2b did not boot"
fi
# Und die Gegenprobe fuer den Pruefer selbst: ein Text, der aus seinem
# Fenster laeuft, muss ERKANNT und nicht falsch gemessen werden.
if [ -s "$TMPD/A2a/desktop.ppm" ]; then
    if python3 tools/look/umlaut.py "$TMPD/A2a/serial.txt" \
            "$TMPD/A2a/desktop.ppm" "Datei-Explorer" "Größe" 64 \
            > "$TMPD/uml-neg.txt" 2>&1; then
        bad "a heading that runs out of its window was measured as good"
    else
        grep -q 'nicht messbar' "$TMPD/uml-neg.txt" \
            && ok "a string past its window edge is refused, not mismeasured" \
            || ok "the narrow window did not draw it at all: $(head -1 "$TMPD/uml-neg.txt")"
    fi
fi

echo "== B. the symbols in the corner =="
if shot B1 lang=de icons=yes nvicons=no keep=yes; then
    S="$TMPD/B1/serial.txt"
    NL=$(grep -a 'taskbar: icon field=net' "$S" | tail -1)
    BL=$(grep -a 'taskbar: icon field=bat' "$S" | tail -1)
    [ -n "$NL" ] && ok "the network has a glyph: $NL" || bad "no network glyph"
    [ -n "$BL" ] && ok "the battery has a glyph: $BL" || bad "no battery glyph"
    NX=$(echo "$NL" | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    NY=$(echo "$NL" | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
    BX=$(echo "$BL" | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    BY=$(echo "$BL" | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
    BAR=$(val "$S" 'taskbar: geom edge=[0-9]+ x=[0-9]+ y=[0-9]+')
    for pair in "net $NX $NY" "bat $BX $BY"; do
        set -- $pair
        I=$(python3 tools/look/inkbox.py "$TMPD/B1/desktop.ppm" "$2" \
            $(( ${BAR:-572} + $3 )) 16 16 255 255 255 | grep -oE 'ink [0-9]+' | grep -oE '[0-9]+')
        # A LINE DRAWING COVERS BETWEEN A TENTH AND A HALF OF ITS BOX.
        # Both ends matter: 0 is a missing glyph, 256 is a filled box.
        if [ "${I:-0}" -ge 25 ] && [ "${I:-0}" -le 200 ]; then
            ok "the $1 symbol really is on the screen: $I ink pixels of 256"
        else
            bad "the $1 symbol measures ${I:-?} ink pixels of 256"
        fi
    done
    NW1=$(val "$S" 'taskbar: field net x=[0-9]+ y=[0-9]+ w=[0-9]+')
fi
if shot B2 lang=de icons=no nvicons=no keep=yes; then
    S="$TMPD/B2/serial.txt"
    grep -qa 'taskbar: icon field=' "$S" \
        && bad "a glyph was reported although there is no icon font" \
        || ok "no icon font, no glyph reported -- the fallback is clean"
    NW2=$(val "$S" 'taskbar: field net x=[0-9]+ y=[0-9]+ w=[0-9]+')
    if [ -n "${NW1:-}" ] && [ -n "${NW2:-}" ]; then
        is "the network field is narrower by exactly the reserved room" \
           "$((NW1 - NW2))" "18"
    fi
    R=$(python3 tools/gfx/checkshot.py ttext "$TMPD/B2/desktop.ppm" \
        assets/osum-sans.ttf 15 579 591 15 23 42 255 255 255 "kein Netz" 8 2>&1)
    case "$R" in
        *", 0 falsch"*) ok "and the text alone is still pixel-exact: $R" ;;
        *) bad "the fallback text is wrong: $R" ;;
    esac
fi

echo "== C. the form tokens =="
R=$(python3 tests/look/rawmetric.py 2>&1 | tail -1)
echo "        $R"
case "$R" in
    *" raw 0") ok "no painting routine names a size: $R" ;;
    *) bad "raw sizes are left in the painting code: $R" ;;
esac
R=$(python3 tests/theme/rawcolour.py 2>&1 | tail -1)
echo "        $R"
case "$R" in
    *" raw 0") ok "and round THEME's rule still holds: $R" ;;
    *) bad "round THEME's colour rule broke: $R" ;;
esac

echo "== D. two appearances, and the contrast in both =="
for v in "classic day light" "modern day light" "modern night dark" "classic night dark"; do
    set -- $v
    n="D-$1-$2"
    if shot "$n" shape=$1 scheme=$2 mode=$3 lang=de extra='einst nostart' keep=yes; then
        S="$TMPD/$n/serial.txt"
        L=$(grep -a 'settings: shape file=' "$S" | tail -1)
        echo "        $L"
        CH=$(echo "$L" | grep -oE ' ctrl_h=[0-9]+' | grep -oE '[0-9]+')
        RB=$(echo "$L" | grep -oE ' radiusb=[0-9]+' | grep -oE '[0-9]+')
        KY=$(echo "$L" | grep -oE ' keys=[0-9]+' | grep -oE '[0-9]+')
        is "$1/$2: keys read out of the shape file" "${KY:-0}" "15"
        if [ "$1" = classic ]; then
            is "$1/$2: control height" "${CH:-0}" "26"
            is "$1/$2: button radius" "${RB:-x}" "0"
        else
            is "$1/$2: control height" "${CH:-0}" "32"
            is "$1/$2: button radius" "${RB:-x}" "6"
        fi
        K=$(grep -aoE 'Text/Akzent [0-9,]+  Akzent/Fläche [0-9,]+  -- WCAG [^ ]+' "$S" | tail -1)
        [ -n "$K" ] && echo "        contrast: $K"
    else
        bad "$n did not boot"
    fi
done
# THE CORNER ITSELF, on the dark pair.
#
# WHERE, AND WHY NOT WHERE THE PROGRAM SAYS. The first version of this
# read the corner at the coordinates the settings program reports for
# its edge chooser, which sounds obviously right and measures nothing:
# in `night`/`dark` the face of a control and the surface of the window
# behind it are THE SAME COLOUR (#1e293b). A rounded corner against an
# identical background has no corner to see -- the probe comes back
# "background 0, antialiased 0" at every offset for five pixels around,
# and it says so whether the corner is round or square.
#
# So it is read at x=12, where a control sits on the DESKTOP
# (#0f172a) and the two colours are 6 : 1 apart. That is a real corner
# of a real widget with a real background behind it, and it is the only
# place in this picture where the question can be answered at all.
# The y comes from the shape: classic controls are 26 high, modern 32,
# so the same widget starts at a different line.
for v in "classic 474 0" "modern 504 2"; do
    set -- $v
    C=$(python3 tools/look/corner.py "$TMPD/D-$1-night/desktop.ppm" 12 "$2" \
        30 41 59 15 23 42 8 2>&1)
    echo "$C" | sed 's/^/        /'
    B=$(echo "$C" | grep -oE 'background [0-9]+' | grep -oE '[0-9]+')
    is "$1: background pixels on the corner diagonal" "${B:-x}" "$3"
done

echo "== E. where the buttons sit =="
# THE NUMBER IS NOT FIXED, AND IT MUST NOT BE.
#
# Where a centred block starts depends on how wide the block is, which
# depends on how many windows are open, and on where the status corner
# begins, which depends on whether there is an icon font on the disk.
# An assertion like "x = 112" passes on one image and fails on the next
# for a reason that has nothing to do with centring -- it happened here
# and it is why this section measures the PROPERTY instead: the run of
# empty bar to the left of the block and the run to its right are the
# same, to within the rounding of one halving.
run_e() { # align
    shot "E-$1" align=$1 lang=de keep=yes || { bad "E-$1 did not boot"; return 1; }
    local S="$TMPD/E-$1/serial.txt"
    SX=$(grep -a 'taskbar: start x=' "$S" | tail -1 | grep -oE 'x=[0-9]+' | grep -oE '[0-9]+')
    SW=$(grep -a 'taskbar: start x=' "$S" | tail -1 | grep -oE ' w=[0-9]+' | grep -oE '[0-9]+')
    # the right edge of the last window button that has a width
    RE=0
    while read -r bx bw; do
        [ -z "$bx" ] && continue
        [ "$bw" = 0 ] && continue
        [ $((bx + bw)) -gt "$RE" ] && RE=$((bx + bw))
    # ONLY COMPLETE LINES. The serial port is shared, and a button line
    # cut in half by the launcher's had `w=416` in it -- the launcher's
    # window, not a taskbar button -- which put the block's right edge
    # 284 pixels past the end of the bar. Requiring the whole shape of
    # the line, up to and including `hidden=`, throws the fragments out.
    done < <(grep -a 'taskbar: btn i=' "$S" \
             | grep -oE ' x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+ hidden=' \
             | sed -E 's/ x=([0-9]+) y=[0-9]+ w=([0-9]+) h=[0-9]+ hidden=/\1 \2/')
    [ "$RE" = 0 ] && RE=$((SX + SW))
    # ONLY A COMPLETE FIELD LINE, and only its own x. A line cut in
    # half by another process can carry two or three `x=` in it, and
    # `grep -o` then hands back three numbers where the caller expects
    # one -- which is an arithmetic error in the shell, not a failed
    # measurement. Anchor on the shape of the whole field record.
    FX=$(grep -a 'taskbar: field net' "$S" \
         | grep -oE ' x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+ lines=' \
         | tail -1 | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
    return 0
}
if run_e left; then
    is "align=left: the start button's x" "${SX:-x}" "4"
    LX=$SX
fi
if run_e center; then
    L=$((SX - 3))
    R=$((FX - 4 - RE))
    D=$((L - R)); [ "$D" -lt 0 ] && D=$((-D))
    echo "        block $SX..$RE  free left $L  free right $R  in a bar of 800"
    if [ "$D" -le 6 ]; then
        ok "align=center: the block is centred in the empty run (left $L, right $R)"
    else
        bad "align=center: left $L against right $R"
    fi
    if [ "${SX:-0}" -gt $(( ${LX:-4} + 50 )) ]; then
        ok "align=center: the start button really moved: $LX -> $SX"
    else
        bad "align=center: the start button did not move: $LX -> ${SX:-?}"
    fi
fi
if shot E-vert align=center edge=left lang=de keep=yes; then
    Y=$(grep -a 'taskbar: start x=' "$TMPD/E-vert/serial.txt" | tail -1 \
        | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
    ge "a vertical bar centres in the HEIGHT: the start button's y" "${Y:-0}" 100
fi

# ---- A, part three: real characters, not transliteration.
#
# Part A of this round proved that a German string RENDERS (438 ink
# pixels on "Ausführen", 0 wrong). It did not check that the German
# strings ARE German. They were not: the editor bundle said "Text
# schreiben und aendern", and a bundle label never goes through the
# catalogue, so no catalogue test could have seen it.
python3 tools/i18n/translit.py --zaehle > "$TMPD/translit.txt" 2>&1
TRC=$?
sed 's/^/        /' "$TMPD/translit.txt"
if [ "$TRC" = 0 ]; then
    ok "no transliteration left in locale/de or in the bundle labels"
else
    bad "transliteration where an umlaut belongs (rc=$TRC)"
fi

echo ""
echo "LOOK: $P passed, $F failed"
[ "$F" = 0 ]
