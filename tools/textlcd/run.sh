#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
HEAVY=/root/jarvis/bin/heavy
export DESIGNBUILD="$TMPD/build"
export OSUM_RTC="base=2026-10-11T11:00:00,clock=vm"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"
SCENE="$ROOT/tools/textlcd/scene.txt"
GATE_MIN=${TEXTLCD_MIN:-400}

$HEAVY bash tools/design/eh6.sh "$TMPD/o0" res=1280x800 accel=kvm nurbau=ja progs="$PROGS" > "$TMPD/build.log" 2>&1 \
    || { echo "build failed"; tail -5 "$TMPD/build.log"; exit 1; }

run_one() {
    $HEAVY bash tools/design/eh6.sh "$TMPD/$1" res=1280x800 accel=kvm uiscale=1 tafel=nein progs="$PROGS" \
        drehbuch="$SCENE" $2 > "$TMPD/$1.log" 2>&1
}
run_one lcd "textsmooth=lcd" &
p1=$!
run_one grey "textsmooth=grey" &
p2=$!
wait $p1 $p2

[ -n "${TEXTLCD_OUT:-}" ] && { mkdir -p "$TEXTLCD_OUT"; for r in lcd grey; do mkdir -p "$TEXTLCD_OUT/$r"; cp "$TMPD/$r"/*.ppm "$TMPD/$r/serial.txt" "$TEXTLCD_OUT/$r/" 2>/dev/null; done; }
for r in lcd grey; do
    [ -s "$TMPD/$r/01-startmenu.ppm" ] || { bad "$r: no picture"; continue; }
    read -r "F_$r" "R_$r" "W_$r" < <(python3 -I tools/textlcd/fringe.py "$TMPD/$r/01-startmenu.ppm")
done
echo "fringe/right/wrong: lcd=${F_lcd:-?}/${R_lcd:-?}/${W_lcd:-?} grey=${F_grey:-?}/${R_grey:-?}/${W_grey:-?}"
if [ -n "${F_lcd:-}" ] && [ -n "${F_grey:-}" ]; then
    [ $((F_lcd - F_grey)) -ge "$GATE_MIN" ] && ok "subpixel text: $((F_lcd - F_grey)) more colour-fringe pixels than grey (>= $GATE_MIN)" \
        || bad "subpixel text: only $((F_lcd - F_grey)) more fringe pixels (< $GATE_MIN)"
    [ "$F_grey" -lt "$F_lcd" ] && ok "counter-proof grey mode: grey text has fewer fringe pixels" || bad "counter-proof grey mode does not change the picture"
    [ "$R_lcd" -ge $((W_lcd * 4)) ] && ok "subpixel order: $R_lcd edge pixels in panel order vs $W_lcd reversed" \
        || bad "subpixel order wrong: $R_lcd in panel order vs $W_lcd reversed"
fi
echo "TEXTLCD: $pass passed, $fail failed"
[ "$fail" = 0 ]
