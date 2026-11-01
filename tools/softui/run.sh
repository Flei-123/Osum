#!/usr/bin/env bash
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
is()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: $2, expected $3"; fi; }
ge()  { if [ "${2:-0}" -ge "$3" ] 2>/dev/null; then ok "$1: $2 (>= $3)"; else bad "$1: ${2:-?}, expected >= $3"; fi; }
le()  { if [ "${2:-999999}" -le "$3" ] 2>/dev/null; then ok "$1: $2 (<= $3)"; else bad "$1: ${2:-?}, expected <= $3"; fi; }

shot() { # dir args...
    local d=$1; shift
    bash tools/look/shot.sh "$TMPD/$d" "$@" > "$TMPD/$d.log" 2>&1
    grep -qa 'qemu exit 21' "$TMPD/$d.log"
}
val() { grep -aoE "$2" "$1" 2>/dev/null | tail -1 | grep -oE '[0-9]+$'; }

echo "== A. classic is unchanged =="
#
#   git worktree add --detach /root/mgline2-base 54bf135
#   cd /root/mgline2-base && FIRNLIB=$(pwd)/lib bash tools/look/shot.sh \
#       /tmp/softui/base-classic shape=classic scheme=day mode=light \
#       keep=yes accel=tcg
#
REF=${SOFTUIBASEPPM:-/tmp/softui/base-classic/desktop.ppm}
if shot A shape=classic scheme=day mode=light keep=yes accel=tcg; then
    ok "classic bootet (QEMU exit 21)"
    if [ -s "$REF" ]; then
        #
        G=$(python3 tools/softui/equal.py "$REF" "$TMPD/A/desktop.ppm" \
            --zeit --ausser 26,62,560,380 2>&1)
        echo "$G" | sed 's/^/        /'
        D=$(echo "$G" | grep -oE 'unterschiedlich [0-9]+' | grep -oE '[0-9]+')
        is "classic: pixels differing from the baseline" "${D:-x}" "0"
    else
        #
        printf '   --    section A skipped: no baseline at %s\n' "$REF"
        printf '         Create it:\n'
        printf '           git worktree add --detach /root/mgline2-base <commit-vor-softui>\n'
        printf '           cd /root/mgline2-base && FIRNLIB=$(pwd)/lib bash tools/look/shot.sh \\\n'
        printf '               /tmp/softui/base-classic shape=classic scheme=day mode=light keep=yes accel=tcg\n'
    fi
else
    bad "classic does not boot"
fi

echo "== B. the shape file is read COMPLETELY =="
if shot B shape=modern scheme=day mode=light keep=yes shadow=on extra='einst nostart wigapp=/bin/explorer'; then
    K=$(val "$TMPD/B/serial.txt" 'shape file=modern name=Modern id=1 keys=[0-9]+')
    is "marks from modern.shape" "${K:-0}" "24"
    CH=$(grep -aoE 'ctrl_h=[0-9]+' "$TMPD/B/serial.txt" | tail -1 | grep -oE '[0-9]+')
    is "ctrl_h from the file" "${CH:-0}" "32"
    N=$(grep -aoE 'form n=[0-9]+' "$TMPD/B/serial.txt" | tail -1 | grep -oE '[0-9]+')
    # r402: three words more (WF_TITLE_BAR, WF_CAP_W, WF_FRAME): 17 -> 20
    # W-S: WF_BLURRIM (edge highlight of blurred surfaces) joined: 20 -> 21
    is "shape words sent to the server" "${N:-0}" "21"
    S=$(stat -c%s assets/shapes/modern.shape)
    ge "and the file is larger than the old buffer" "$S" "4097"
else
    bad "modern does not boot"
fi

echo "== C. the shadow: mask against rings against none =="
if [ -s "$TMPD/B/serial.txt" ]; then
    L=$(grep -a 'wmbench2: maske' "$TMPD/B/serial.txt" | tail -1)
    R=$(grep -a 'wmbench2: ringe' "$TMPD/B/serial.txt" | tail -1)
    O=$(grep -a 'wmbench2: without' "$TMPD/B/serial.txt" | tail -1)
    echo "        $O"
    echo "        $L"
    echo "        $R"
    MU=$(echo "$L" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    RU=$(echo "$R" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    OU=$(echo "$O" | grep -oE 'full=[0-9]+' | grep -oE '[0-9]+')
    MA=$(echo "$L" | grep -oE 'aapx=[0-9]+' | grep -oE '[0-9]+')
    RA=$(echo "$R" | grep -oE 'aapx=[0-9]+' | grep -oE '[0-9]+')
    OA=$(echo "$O" | grep -oE 'aapx=[0-9]+' | grep -oE '[0-9]+')
    if [ -n "$MU" ] && [ -n "$RU" ] && [ -n "$OU" ]; then
        MK=$((MU - OU)); RK=$((RU - OU))
        echo "        shadow cost: mask ${MK} us, rings ${RK} us"
        if [ "$MK" -lt "$RK" ]; then
            ok "the mask is cheaper than the rings ($MK < $RK us)"
        else
            bad "the mask is NOT cheaper ($MK against $RK us)"
        fi
    else
        bad "no timing in the capture"
    fi
    if [ -n "$MA" ] && [ -n "$RA" ] && [ -n "$OA" ]; then
        le "shadow corner samples per frame with the mask (without the shadowless baseline $OA)" \
            "$((MA - OA))" "$(((RA - OA) / 4))"
    fi
    SB=$(val "$TMPD/B/serial.txt" 'shbuild=[0-9]+')
    le "the mask was built once per run" "${SB:-99}" "1"
    ge "and it was built at all" "${SB:-0}" "1"
fi

echo "== D. the three buttons, and the red one =="
# TWO PICTURES, because the pointer cannot be on the close button and off it at
# once: D0 has no pointer on the bar (the three SHAPES: stroke, square, cross),
# D has it on the close button (the HOVER state: red face, white cross).
# The close button of the 1004 px wide Settings window at x=20: centre 1007,14 (was 767,14 for the old 764 px window).
if shot D0 shape=modern scheme=day mode=light keep=yes extra='einst nostart'; then
    python3 tools/softui/knoepfe.py "$TMPD/D0/desktop.ppm" \
        "$TMPD/D0/serial.txt" > "$TMPD/D0.knopf" 2>&1
else
    : > "$TMPD/D0.knopf"
fi
if shot D shape=modern scheme=day mode=light keep=yes extra='einst nostart' hover=1007,14; then
    python3 tools/softui/knoepfe.py "$TMPD/D/desktop.ppm" \
        "$TMPD/D/serial.txt" > "$TMPD/D.hover" 2>&1
    { cat "$TMPD/D0.knopf"; grep -a '^hover:' "$TMPD/D.hover"; } > "$TMPD/D.knopf"
    cat "$TMPD/D.knopf" | sed 's/^/        /'
    grep -q 'min: stroke ok' "$TMPD/D.knopf" \
        && ok "Minimise is a horizontal stroke" \
        || bad "Minimise is not a stroke"
    grep -q 'max: square ok' "$TMPD/D.knopf" \
        && ok "Maximise is a square" || bad "Maximise is not a square"
    grep -q 'close: cross ok' "$TMPD/D.knopf" \
        && ok "Close is a cross" || bad "Close is not a cross"
    grep -q 'hover: red ok' "$TMPD/D.knopf" \
        && ok "the hovered close button is red with a white cross" \
        || bad "the hover state is missing"
    grep -q 'macos: no circles' "$TMPD/D.knopf" \
        && ok "and there are NO three coloured circles" \
        || bad "there are coloured circles"
fi

echo "== E. the focus, without a loud colour =="
# The focused window has to stand far enough from the screen edge for its shadow
# to be measured (fokus.py skips x < 24): the Settings window opens at x=20, so
# this picture has the file manager as the only extra window (it gets the focus).
if shot E0 shape=modern scheme=day mode=light keep=yes shadow=on extra='nostart wigapp=/bin/explorer'; then
    python3 tools/softui/fokus.py "$TMPD/E0/desktop.ppm" \
        "$TMPD/E0/serial.txt" > "$TMPD/E.txt" 2>&1
    cat "$TMPD/E.txt" | sed 's/^/        /'
    AT=$(grep -E '^aktiv ' "$TMPD/E.txt" | grep -oE 'tiefe=[0-9]+' | grep -oE '[0-9]+')
    IT=$(grep -E '^inaktiv ' "$TMPD/E.txt" | grep -oE 'tiefe=[0-9]+' | grep -oE '[0-9]+')
    if [ -n "$AT" ] && [ -n "$IT" ] && [ "$IT" -gt 0 ]; then
        if [ "$AT" -gt "$((IT * 3 / 2))" ]; then
            ok "the shadow of the sharp window is at least 1.5 times as deep ($AT against $IT)"
        else
            bad "the two shadows are too similar ($AT against $IT)"
        fi
    else
        bad "no two shadows measured"
    fi
    grep -q 'title: no accent' "$TMPD/E.txt" \
        && ok "and no title bar carries the accent" \
        || bad "a title bar is still accent-coloured"
fi

echo "== F. the contrast =="
#
for v in "day light 516" "night dark 1236"; do
    set -- $v
    if shot "F-$1" shape=modern scheme=$1 mode=$2 keep=yes extra='einst nostart'; then
        M=$(python3 tools/theme/model.py contrast "assets/schemes/$1.scheme" $2 \
            | awk '$1=="on-accent"&&$2=="accent"{print $6}')
        is "$1/$2: text/accent in the model (x100), unchanged" "${M:-0}" "$3"
        W=$(python3 tools/theme/model.py contrast "assets/schemes/$1.scheme" $2 \
            | awk '$3=="normal"{print $6}' | sort -n | head -1)
        echo "        smallest text pair in the model: $W"
        K=$(python3 tools/softui/title.py "$TMPD/F-$1/desktop.ppm" \
            "$TMPD/F-$1/serial.txt" 2>&1 | tail -1)
        echo "        $K"
        R=$(echo "$K" | grep -oE 'ratio [0-9]+' | grep -oE '[0-9]+')
        ge "$1/$2: title text in the IMAGE, measured" "${R:-0}" "$(( $3 / 100 ))"
    fi
done

echo "== G. the images are measured =="
for d in B D F-day F-night; do
    if [ -s "$TMPD/$d/desktop.ppm" ]; then
        python3 tools/softui/check.py "$TMPD/$d/desktop.ppm" \
            "$TMPD/$d/serial.txt" > "$TMPD/$d.pruef" 2>&1
        R=$?
        tail -1 "$TMPD/$d.pruef" | sed 's/^/        /'
        if [ $R -eq 0 ]; then
            ok "$d: no empty, clipped or overlapping label"
        else
            bad "$d: remarks"
            head -8 "$TMPD/$d.pruef" | sed 's/^/          /'
        fi
    fi
done

echo
echo "SOFTUI: $P passed, $F failed"
[ "$F" -eq 0 ]
