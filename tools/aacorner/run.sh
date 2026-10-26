#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/aacorner/run.sh -- THE RIM OF A POPUP FOLLOWS THE ARC, WITH COVERAGE ALPHA.
#
#   bash tools/aacorner/run.sh
#
# Justin's finding from the real Dell (OptiPlex 9020): the corners and the rim
# of the right-click menu (and of the other popups) are pixelated.
#
# CAUSE (measured, serial + pictures): the window server cuts every frameless
# window to the window radius (`wm.nodeco_radius`, 8 points in the osum
# shape) with coverage alpha -- but the CLIENTS painted something else under
# that cut:
#   * the menu (`wlib.paint_menu`) a SQUARE accent frame on the window edge --
#     the cut chewed the frame at the four corners: the rim ended in the air
#     and the arc itself had no rim at all;
#   * the tooltip and the toast (`barpop.fi`) a plate and a ring with the
#     BUTTON radius (8) -- two different circles: a dark fringe between the
#     ring and the fill, rim pixels the server removed.
# FIX: the window is painted in the rim colour, the fill is a rounded plate one
# point inside (radius - 1); client radius = server radius (`wlibc.win_round`).
#
# WHAT THIS MEASURES (tools/aacorner/aacorner.py, one line per surface):
#   For the menu, the tooltip, the toast, at scale 1 and 2: the corner squares
#   are compared with an ideal rounded corner (8x8 supersampling, rim 1 pixel,
#   pure colours taken from the straight edge): `bad` = pixels more than 12
#   levels off (dark fringe, rim ending in the air), `soft` = arc pixels that
#   carry coverage alpha (a staircase has none).
#   GATE: bad == 0 ... small, soft > 0 for every surface, and the COUNTER-PROOF
#   `aa_old=1` (theme.conf: the old drawing) must be RED (bad >> gate).
#
# The four VM runs (scale 1/2 x new/old) are four `heavy` jobs of their own.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
HEAVY=/root/jarvis/bin/heavy
BUILD=${AA_BUILD:-$TMPD/build}
export DESIGNBUILD="$BUILD"
export OSUM_RTC="base=2026-10-11T11:00:00,clock=vm"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
SCENE="$ROOT/tools/aacorner/scene.txt"
GATE_BAD=${AA_GATE_BAD:-6}     # pixels off by more than 12 levels, per surface
GATE_OLD=${AA_GATE_OLD:-20}    # the counter-proof must have at least this many (sum over surfaces)

# 1. build once (the four runs share the kernel and the programs)
$HEAVY bash tools/design/eh6.sh "$TMPD/o0" res=1280x800 accel=kvm nurbau=ja progs="$PROGS" > "$TMPD/build.log" 2>&1 \
    || { echo "build failed"; tail -5 "$TMPD/build.log"; exit 1; }

# 2. four runs, each its own heavy job
run_one() {  # name scale extra
    $HEAVY bash tools/design/eh6.sh "$TMPD/$1" res=1280x800 accel=kvm uiscale=$2 tafel=nein progs="$PROGS" \
        drehbuch="$SCENE" themeextra="$3" > "$TMPD/$1.log" 2>&1
}
run_one new1 1 "" &
p1=$!
run_one old1 1 "aa_old=1" &
p2=$!
run_one new2 2 "" &
p3=$!
run_one old2 2 "aa_old=1" &
p4=$!
wait $p1 $p2 $p3 $p4

# 3. measure
[ -n "${AA_OUT:-}" ] && { mkdir -p "$AA_OUT"; for r in new1 old1 new2 old2; do mkdir -p "$AA_OUT/$r"; cp "$TMPD/$r"/*.ppm "$TMPD/$r/serial.txt" "$AA_OUT/$r/" 2>/dev/null; done; }
RADIUS=$(grep -E '^radius_window=' assets/shapes/osum.shape | head -1 | cut -d= -f2)
RADIUS=${RADIUS:-12}
# fields: name file regexp-for-rectangle corners
measure() {  # run name
    local o=$TMPD/$1 s=$TMPD/$1/serial.txt line x y w h SC=${1: -1}
    [ -s "$s" ] || { bad "$1: no serial"; return 1; }
    # tooltip: `wlib: tip [..] x= y= w= h=`
    line=$(grep -a 'wlib: tip \[' "$s" | head -1)
    x=$(sed -E 's/.* x=([0-9]+).*/\1/' <<<"$line"); y=$(sed -E 's/.* y=([0-9]+).*/\1/' <<<"$line")
    w=$(sed -E 's/.* w=([0-9]+).*/\1/' <<<"$line"); h=$(sed -E 's/.* h=([0-9]+).*/\1/' <<<"$line")
    w=$(( (w + SC - 1) / SC * SC )); h=$(( (h + SC - 1) / SC * SC ))
    TIP=$(python3 -I tools/aacorner/aacorner.py "$o/01-tip.ppm" "$x" "$y" "$w" "$h" "$RADIUS")
    # toast: `taskbar: toast [..] x= y= w= h=`; the left stripe is not the rim: top right corner only (the toast below it, and the shadow, cover the lower ones)
    line=$(grep -a 'taskbar: toast \[' "$s" | tail -1)
    x=$(sed -E 's/.* x=([0-9]+).*/\1/' <<<"$line"); y=$(sed -E 's/.* y=([0-9]+).*/\1/' <<<"$line")
    w=$(sed -E 's/.* w=([0-9]+).*/\1/' <<<"$line"); h=$(sed -E 's/.* h=([0-9]+).*/\1/' <<<"$line")
    w=$(( (w + SC - 1) / SC * SC )); h=$(( (h + SC - 1) / SC * SC ))
    TOAST=$(python3 -I tools/aacorner/aacorner.py "$o/03-toast.ppm" "$x" "$y" "$w" "$h" "$RADIUS" tr)
    # context menu: the last popup-layer window (`lay=5`) the server listed before the picture
    line=$(grep -a 'wm: fen .* lay=5 ' "$s" | tail -1)
    x=$(sed -E 's/.* x=([0-9]+) .*/\1/' <<<"$line"); y=$(sed -E 's/.* y=([0-9]+) .*/\1/' <<<"$line")
    w=$(sed -E 's/.* w=([0-9]+) .*/\1/' <<<"$line"); h=$(sed -E 's/.* h=([0-9]+) .*/\1/' <<<"$line")
    # a tooltip may overlap the lower corners of the menu: the upper ones are judged
    MENU=$(python3 -I tools/aacorner/aacorner.py "$o/04-ctxmenu.ppm" "$x" "$y" "$w" "$h" "$RADIUS" tl,tr)
    echo "$1 tip   [$TIP]"; echo "$1 toast [$TOAST]"; echo "$1 menu  [$MENU]"
}
sumbad() { local t=0 v; for v in "$@"; do t=$((t + $(sed -E 's/.*bad=([0-9]+).*/\1/' <<<"$v"))); done; echo $t; }
field() { sed -E "s/.*$2=([0-9]+).*/\1/" <<<"$1"; }

for sc in 1 2; do
    measure new$sc; N_TIP=$TIP; N_TOAST=$TOAST; N_MENU=$MENU
    measure old$sc; O_TIP=$TIP; O_TOAST=$TOAST; O_MENU=$MENU
    for k in TIP TOAST MENU; do
        v=N_$k; v=${!v}
        b=$(field "$v" bad); s=$(field "$v" soft)
        [ "$b" -le "$GATE_BAD" ] && ok "scale $sc $k: bad=$b <= $GATE_BAD" || bad "scale $sc $k: bad=$b > $GATE_BAD ($v)"
        [ "$s" -gt 0 ] && ok "scale $sc $k: arc has coverage alpha (soft=$s)" || bad "scale $sc $k: arc is a staircase (soft=0)"
    done
    ob=$(sumbad "$O_TIP" "$O_TOAST" "$O_MENU")
    [ "$ob" -ge "$GATE_OLD" ] && ok "scale $sc counter-proof aa_old=1: bad=$ob (>= $GATE_OLD, red as it must be)" \
        || bad "scale $sc counter-proof aa_old=1: only bad=$ob, the test does not see the old drawing"
done
echo "AACORNER: $pass passed, $fail failed"
[ "$fail" = 0 ]
