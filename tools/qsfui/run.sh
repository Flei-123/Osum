#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/qsfui/run.sh -- THE QUICK SETTINGS ARE A TREE OF fUi (05.10.2026).
#
#   bash tools/qsfui/run.sh [<uiscale> ...]        (default: 1 2)
#
# The panel of the task bar (kernel/user/qs.fi) used to paint itself: a band
# loop over wlibc/wlib primitives, hit tests by hand, a poll of the window's
# event ring. Now it is window 1 of the task bar's scene host (window 0 is the
# bar's own wlib window, `fuiscene.foreign_main`): a card with tiles (a button
# face of fUi plus the program's own picture), two sliders of fUi, a separator
# and a footer with icon buttons.
#
# What this run measures, on the machine of the stick (tools/design/eh6.sh:
# USB keyboard and mouse, 4 cores), at ui_scale 1 and 2:
#   1. Super+A opens the panel, it reports its geometry, it lies on the screen
#   2. the four tiles are as wide as the design says (117 points) and
#      kachel.py, fed with the rectangles THE PANEL REPORTS, finds no label
#      over a tile's edge and no two rows touching
#   3. a click on the "Tiling" tile reaches the system (`qs: tile n=5 to=1`)
#      and the tile is drawn on the accent colour afterwards (pixels)
#   4. a click into the brightness slider sets the brightness to the middle of
#      its range (`qs: hell auf =`), and the knob moved (pixels)
#   5. Escape closes the panel (the window has the keyboard: `closed by
#      escape`), Super+A opens it again and closes it again
#   COUNTER-PROOF: kachel.py with a rectangle moved half a tile to the right
#   must complain -- otherwise step 2 measures nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SCALES=${*:-"1 2"}

cat > "$TMPD/dreh.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 5
taste meta_l-a
warteauf 'qs: open' || 30
warte 2
foto 01-open
klickauf qskachel5
warte 2
foto 02-tile
klickauf hellspur
warte 2
foto 03-slider
taste esc
warte 3
foto 04-closed
taste meta_l-a
warte 3
taste meta_l-a
warte 3
EOF

# a pixel of a picture: px <file.ppm> <x> <y>  ->  "r g b"
px() {
    python3 - "$1" "$2" "$3" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
f = []; at = 2
while len(f) < 3:
    while d[at:at+1].isspace(): at += 1
    s = at
    while not d[at:at+1].isspace(): at += 1
    f.append(int(d[s:at]))
at += 1
w, h, _ = f
x, y = int(sys.argv[2]), int(sys.argv[3])
o = at + (y * w + x) * 3
print(d[o], d[o+1], d[o+2])
PY
}

for sc in $SCALES; do
    echo "== ui_scale $sc =="
    res=1280x800
    [ "$sc" != 1 ] && res=1920x1080
    D="$TMPD/s$sc"
    # a key press that is lost on a loaded host (no `qs: open`) is tried once more
    for try in 1 2; do
        rm -rf "$D"
        bash tools/design/eh6.sh "$D" res=$res uiscale=$sc accel=kvm drehbuch="$TMPD/dreh.txt" \
            > "$TMPD/s$sc.log" 2>&1
        grep -aq '^qs: open ' "$D/serial.txt" 2>/dev/null && break
        echo "        (try $try: the panel did not open)"
    done
    S="$D/serial.txt"
    # QSFUI_OUT=<dir>: keep the pictures and the serial line for a human
    if [ -n "${QSFUI_OUT:-}" ]; then
        mkdir -p "$QSFUI_OUT/s$sc"; cp "$D"/*.ppm "$S" "$QSFUI_OUT/s$sc/" 2>/dev/null
    fi
    if [ ! -s "$D/01-open.ppm" ]; then
        bad "scale $sc: no pictures ($(tail -n 2 "$TMPD/s$sc.log" | tr '\n' ' '))"
        continue
    fi
    # 1. the panel opened and says where
    open=$(grep -aoE '^qs: open x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$S" | head -1)
    if [ -z "$open" ]; then bad "scale $sc: no 'qs: open'"; continue; fi
    qx=$(echo "$open" | sed -E 's/.* x=([0-9]+).*/\1/'); qy=$(echo "$open" | sed -E 's/.* y=([0-9]+).*/\1/')
    qw=$(echo "$open" | sed -E 's/.* w=([0-9]+).*/\1/'); qh=$(echo "$open" | sed -E 's/.* h=([0-9]+).*/\1/')
    XR=${res%x*}; YR=${res#*x}
    if [ $((qx + qw)) -le "$XR" ] && [ $((qy + qh)) -le "$YR" ]; then
        ok "scale $sc: the panel opens at $qx,$qy ${qw}x$qh on a ${res} screen"
    else
        bad "scale $sc: the panel $qx,$qy ${qw}x$qh does not lie on the screen"
    fi
    # 2. the tiles
    rects=(); ws=()
    while read -r kx ky kw kh; do
        rects+=("$((qx + kx)),$((qy + ky)),$kw,$kh"); ws+=("$kw")
    done < <(grep -aoE '^qs: kachel n=[0-9]+ platz=[0-9]+ x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$S" \
        | head -4 | sed -E 's/.* x=([0-9]+) y=([0-9]+) w=([0-9]+) h=([0-9]+)/\1 \2 \3 \4/')
    if [ "${#rects[@]}" -ne 4 ]; then bad "scale $sc: the panel reported ${#rects[@]} tiles, not 4"; continue; fi
    allw=1
    for w in "${ws[@]}"; do [ "$w" -eq $((117 * sc)) ] || allw=0; done
    [ "$allw" = 1 ] && ok "scale $sc: every tile is $((117 * sc)) pixels wide (117 points)" \
        || bad "scale $sc: tile widths ${ws[*]}, expected $((117 * sc))"
    r=$(python3 tools/netview/kachel.py "$D/01-open.ppm" --rects $((33 * sc)) $((12 * sc)) "${rects[@]}" 2>&1 | tail -n 1)
    case "$r" in ok*) ok "scale $sc: the tiles hold their labels -- $r" ;;
                 *)   bad "scale $sc: tile layout: $r" ;; esac
    # COUNTER-PROOF: the same measurement on rectangles moved half a tile sideways
    mv=()
    for rc in "${rects[@]}"; do
        IFS=, read -r a b c d <<< "$rc"; mv+=("$((a + c / 2)),$b,$c,$d")
    done
    r=$(python3 tools/netview/kachel.py "$D/01-open.ppm" --rects $((33 * sc)) $((12 * sc)) "${mv[@]}" 2>&1 | tail -n 1)
    case "$r" in FALSCH*) ok "scale $sc: counter-proof -- shifted tiles are refused" ;;
                 *)   bad "scale $sc: counter-proof -- shifted tiles were accepted ($r)" ;; esac
    # 3. the Tiling tile (n=5)
    if grep -aqE '^qs: tile n=5 to=1 rc=0' "$S"; then
        ok "scale $sc: a click on the Tiling tile reached the system (to=1)"
    else
        bad "scale $sc: no 'qs: tile n=5 to=1 rc=0'"
    fi
    IFS=, read -r tx ty tw th <<< "${rects[3]}"
    cx=$((tx + 3 * sc)); cy=$((ty + th / 2))
    a=$(px "$D/01-open.ppm" "$cx" "$cy"); b=$(px "$D/02-tile.ppm" "$cx" "$cy")
    if [ "$a" != "$b" ]; then
        ok "scale $sc: the tile changed its colour ($a -> $b)"
    else
        bad "scale $sc: the tile looks the same after the click ($a)"
    fi
    # 4. the slider
    hv=$(grep -aoE '^qs: hell auf =[0-9]+' "$S" | head -1 | grep -oE '[0-9]+$')
    if [ -n "$hv" ] && [ "$hv" -ge 100 ] && [ "$hv" -le 120 ]; then
        ok "scale $sc: a click in the middle of the brightness slider sets $hv (range 20..200)"
    else
        bad "scale $sc: brightness after the click: ${hv:-nothing}"
    fi
    sp=$(grep -aoE '^qs: hell spur von=[0-9]+ bis=[0-9]+ ym=[0-9]+' "$S" | head -1)
    ym=$(echo "$sp" | sed -E 's/.* ym=([0-9]+).*/\1/'); von=$(echo "$sp" | sed -E 's/.* von=([0-9]+).*/\1/')
    bis=$(echo "$sp" | sed -E 's/.* bis=([0-9]+).*/\1/')
    # the knob: at the middle of the track the picture shows the track before
    # the click (the knob stood at about 44 %) and the knob after it
    mx=$(( (von + bis) / 2 ))
    a=$(px "$D/01-open.ppm" "$mx" "$ym"); b=$(px "$D/03-slider.ppm" "$mx" "$ym")
    if [ "$a" != "$b" ]; then
        ok "scale $sc: the brightness knob moved to the middle of the track ($a -> $b at $mx,$ym)"
    else
        bad "scale $sc: nothing changed at the middle of the track ($a at $mx,$ym)"
    fi
    # 5. the keyboard
    if grep -aq '^qs: closed by escape' "$S"; then ok "scale $sc: Escape closes the panel"
    else bad "scale $sc: Escape did not close the panel"; fi
    n_open=$(grep -ac '^qs: open ' "$S")
    if [ "$n_open" -eq 2 ] && grep -aq '^qs: closed by hotkey' "$S"; then
        ok "scale $sc: Super+A opens it again ($n_open openings) and closes it again"
    else
        bad "scale $sc: openings $n_open, closed by hotkey: $(grep -ac '^qs: closed by hotkey' "$S")"
    fi
done
echo; echo "QSFUI: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
