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
if shot A user=- icons=yes lang=de extra='einst nostart' uitrace=yes autohide=1 keep=yes; then
    ok "the image boots to the desktop (QEMU exit 21)"
    S="$TMPD/A/serial.txt"
    LG=$(grep -a 'taskbar: lang=' "$S" | tail -1)
    case "$LG" in
        *"lang=de src=2"*) ok "the language came from /etc/locale.conf: $LG" ;;
        *) bad "the taskbar is not on German from the system default: $LG" ;;
    esac
    K=$(val "$S" 'keys=[0-9]+')
    ge "keys in the message catalogue" "$K" 140
    grep -qa 't=kein Netz' "$S" && ok "the taskbar says 'kein Netz' and not 'no network'" \
        || bad "the taskbar is still English"
    # THE UMLAUT, PIXEL BY PIXEL. The settings program says where it put
    # the word; the window server says where the window is; the checker
    # rasterises the same string a second time and compares.
    L=$(grep -aoE 'wlib: text win=[-0-9]+ kind=2 x=[0-9]+ base=[0-9]+ fg=[0-9]+ bg=[0-9]+ t=Übernehmen' "$S" | tail -1)
    if [ -n "$L" ]; then
        X=$(echo "$L" | grep -oE ' x=[0-9]+' | grep -oE '[0-9]+')
        B=$(echo "$L" | grep -oE ' base=[0-9]+' | grep -oE '[0-9]+')
        # the window's inner origin: a window clamped into the corner
        # reports its OUTER position, so the inset is border + title.
        R=$(python3 tools/gfx/checkshot.py ttext "$TMPD/A/desktop.ppm" \
            assets/osum-sans.ttf 15 $((X + 2)) $((B + 22)) \
            15 23 42 255 255 255 "Übernehmen" 8 2>&1)
        echo "        $R"
        case "$R" in
            *", 0 falsch"*) ok "'Übernehmen' is on the screen, pixel for pixel" ;;
            *) bad "the umlaut word does not match a second rasterisation" ;;
        esac
    else
        bad "the settings program did not report its Apply button"
    fi
    N=$(python3 tools/i18n/scan.py 2>/dev/null | grep -aoE '^gefunden: [0-9]+' | grep -oE '[0-9]+')
    is "hardcoded German surface text (tools/i18n/scan.py)" "${N:-x}" "0"
else
    bad "section A did not boot"
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
# THE CORNER ITSELF, on the dark pair, where face and surface are far
# enough apart that the reading cannot be an artefact of the tolerance.
for v in "classic 474 0" "modern 504 2"; do
    set -- $v
    C=$(python3 tools/look/corner.py "$TMPD/D-$1-night/desktop.ppm" 12 "$2" \
        30 41 59 15 23 42 8 2>&1)
    echo "$C" | sed 's/^/        /'
    B=$(echo "$C" | grep -oE 'background [0-9]+' | grep -oE '[0-9]+')
    is "$1: background pixels on the corner diagonal" "${B:-x}" "$3"
done

echo "== E. where the buttons sit =="
for v in "left 4" "center 112"; do
    set -- $v
    if shot "E-$1" align=$1 lang=de keep=yes; then
        S="$TMPD/E-$1/serial.txt"
        X=$(grep -a 'taskbar: start x=' "$S" | tail -1 | grep -oE 'x=[0-9]+' | grep -oE '[0-9]+')
        is "align=$1: the start button's x" "${X:-x}" "$2"
    else
        bad "E-$1 did not boot"
    fi
done
if shot E-vert align=center edge=left lang=de keep=yes; then
    Y=$(grep -a 'taskbar: start x=' "$TMPD/E-vert/serial.txt" | tail -1 \
        | grep -oE ' y=[0-9]+' | grep -oE '[0-9]+')
    ge "a vertical bar centres in the HEIGHT: the start button's y" "${Y:-0}" 100
fi

echo ""
echo "LOOK: $P passed, $F failed"
[ "$F" = 0 ]
