#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/touchgest/run.sh -- gate for the touchpad gesture machine (L-002 r756).
#
# WHAT IT MEASURES
#   1. lib/touchgest/gest.fi compiles for the app AND the kernel profile.
#   2. tools/touchgest/oracle.fi (host program, same lib file) drives the
#      machine with synthetic finger frames and answers every promise with
#      OK: taps (1/2/3 fingers, timing edge, wobble, button), pointer slop,
#      two finger scroll, pinch in/out, three finger swipe (4 directions,
#      once per phase), edge strips, palm rejection (size, typing), phase
#      changes without a pointer jump, independent devices.
#   3. NEGATIVE CONTROLS: the same oracle against a lib with one rule
#      broken must go red. An oracle that cannot fail measures nothing.
#
# WHAT IT DOES NOT MEASURE (stated, not hidden)
#   No real touchpad. Thresholds are guesses relative to the pad size.
#   Whether hidin.fi feeds the machine is measured by tools/hid/run.sh.
#
# Usage: bash tools/touchgest/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$ROOT/lib"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

[ -f lib/touchgest/gest.fi ] && ok "lib/touchgest/gest.fi exists" || bad "gest.fi missing"
[ -f tools/touchgest/oracle.fi ] && ok "oracle.fi exists" || bad "oracle.fi missing"
printf 'import touchgest.gest\nfn main() -> i32 {\n    gest.reset(0)\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "lib compiles with --profile=kernel" \
    || { bad "lib does not compile with --profile=kernel"; head -5 "$T/k.err"; }
"$FIRNC" tools/touchgest/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds against lib/touchgest" \
    || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 40 ] && ok "oracle: $nok promises OK (>= 40)" || bad "oracle: only $nok OK (< 40)"
    pass=$((pass+nok))
fi

"$FIRNC" tools/touchgest/oracle2.fi -o "$T/oracle2" 2> "$T/o2.err" \
    && ok "oracle2 (TPSET options) builds against lib/touchgest" \
    || { bad "oracle2 does not build"; head -10 "$T/o2.err"; }
if [ -x "$T/oracle2" ]; then
    "$T/oracle2" > "$T/out2.txt" 2>&1
    nok=$(grep -c '^OK' "$T/out2.txt")
    nbad=$(grep -c '^FAIL' "$T/out2.txt")
    sed -n 's/^FAIL /  FAIL  oracle2: /p' "$T/out2.txt"
    [ "$nbad" = 0 ] && ok "oracle2: no FAIL line" || bad "oracle2: $nbad FAIL lines"
    [ "$nok" -ge 55 ] && ok "oracle2: $nok promises OK (>= 55)" || bad "oracle2: only $nok OK (< 55)"
    pass=$((pass+nok))
fi

"$FIRNC" tools/touchgest/oracle_direct.fi -o "$T/oracle_direct" 2> "$T/od.err" \
    && ok "oracle_direct (touch screen gestures) builds against lib/touchgest" \
    || { bad "oracle_direct does not build"; head -10 "$T/od.err"; }
if [ -x "$T/oracle_direct" ]; then
    "$T/oracle_direct" > "$T/outd.txt" 2>&1
    nok=$(grep -c '^OK' "$T/outd.txt")
    nbad=$(grep -c '^FAIL' "$T/outd.txt")
    sed -n 's/^FAIL /  FAIL  oracle_direct: /p' "$T/outd.txt"
    [ "$nbad" = 0 ] && ok "oracle_direct: no FAIL line" || bad "oracle_direct: $nbad FAIL lines"
    [ "$nok" -ge 80 ] && ok "oracle_direct: $nok promises OK (>= 80)" || bad "oracle_direct: only $nok OK (< 80)"
    pass=$((pass+nok))
fi

# negative controls: break one rule at a time in a copy of the lib
mutate() { # name sed-expression [oracle] [lib file]
    local name=$1 expr=$2 orc=${3:-tools/touchgest/oracle.fi} lf=${4:-gest.fi}
    local L="$T/lib-$name"
    mkdir -p "$L"
    for d in lib/*; do
        [ "$(basename "$d")" = touchgest ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    mkdir -p "$L/touchgest"
    cp lib/touchgest/*.fi "$L/touchgest/"
    sed -e "$expr" "lib/touchgest/$lf" > "$L/touchgest/$lf"
    if cmp -s "lib/touchgest/$lf" "$L/touchgest/$lf"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" "$orc" -o "$T/o-$name" 2>/dev/null; then
        bad "control $name: mutated oracle does not build"
        return
    fi
    local nf
    nf=$("$T/o-$name" 2>&1 | grep -c '^FAIL')
    [ "$nf" -gt 0 ] && ok "control $name: oracle goes red ($nf FAIL)" \
                     || bad "control $name: oracle stays green on a broken lib"
}
mutate notapwindow 's/dur <= d_tapms\[d\]/dur <= 100000/'
mutate nopalmsize  's/if d_palm\[d\] != 0 \&\& size >= d_palm\[d\] {/if false {/'
mutate notyping    's/f_now - d_last_key\[d\] < TYPING_MS/f_now < 0/'
mutate notypingopt 's/if get_opt(dev, O_TYPING) != 0 \&\& d_have_key/if d_have_key/'
mutate noenabled  's/if get_opt(f_dev, O_ENABLED) == 0 { return }//'
mutate noslop      's/if geom.absv(x - c_lx\[k\]) + geom.absv(y - c_ly\[k\]) > sl2 {/if geom.absv(x - c_lx[k]) + geom.absv(y - c_ly[k]) > 0 {/'
mutate nopinch     's/if dd > tr {/if false {/'
mutate swipeagain  's/if d_fired\[d\] == 0 {/if true {/'
mutate noedge      's/if c_edge\[k\] == 1 {/if false {/'
mutate rightclick  's/emit(EV_CLICK, 2, 0)/emit(EV_CLICK, 1, 0)/'
mutate nobutton    's/d_btn\[d\] == 0 \&\&//'
mutate noedgemotion 's/if qx != 0 || qy != 0 { emit(EV_MOVE, qx, qy) }//'
mutate edgeheld    's/if c_edge\[k\] == 0 \&\& ((d_pbtn\[d\] \& 1) != 0 || d_drag\[d\] != 0) {/if c_edge[k] == 0 {/'
mutate edgeinward  's/dir \* move_d < 0 \&\& geom.absv(move_d) > slop_v \/ 4/false/'
mutate edgeliftoff 's/if n != 1 { d_em\[d\] = 0 }//'
mutate onedev      's/let d: usize = dev as usize/let d: usize = 0/g'

O2=tools/touchgest/oracle2.fi
mutate nonatural  's/if get_opt(dev, O_NATURAL) != 0 {/if false {/' $O2
mutate noscale    's/if pct != 100 {/if false {/' $O2
mutate nodrag     's/emit(EV_DRAG, 1, 0)/emit(EV_DRAG, 0, 0)/' $O2
mutate dragwindow 's/now - d_lastclick\[d\] <= get_opt(dev, O_DRAG_MS)/now - d_lastclick[d] <= 100000/' $O2
mutate nocorner   's/d_bmap\[d\] = 1$/d_bmap[d] = 0/' $O2
mutate nomomentum 's/d_mom\[d\] = 1$/d_mom[d] = 0/' $O2
mutate nodecay    's/d_vy\[d\] = d_vy\[d\] - geom.sdiv(d_vy\[d\] \* dt, MOM_TAU_MS)/d_vy[d] = d_vy[d]/' $O2
mutate notapopt   's/if get_opt(dev, O_TAP) != 0 {$/if true {/' $O2
mutate notap2opt  's/if get_opt(dev, O_TAP2) != 0 { emit/if true { emit/' $O2
mutate nopinchopt 's/if get_opt(dev, O_PINCH) == 0 { d_lock\[d\] = 3 }//' $O2
mutate noscrollopt 's/if get_opt(dev, O_SCROLL) == 0 { return }//' $O2
mutate noactions  's/if dir == 3 { return A_TASKVIEW }/if dir == 3 { return A_NONE }/' $O2
mutate nolatch    's/^        d_bmap\[d\] = 0$/        d_bmap[d] = d_bmap[d]/' $O2
mutate noclamp    's/if v > 500 { v = 500 }//' $O2

OD=tools/touchgest/oracle_direct.fi
LD=direct.fi
mutate dlongtime   's/if get_opt(dev, O_LONG) != 0 \&\& now >= d_t0\[d\] + get_opt(dev, O_LONG_MS) {/if false {/' $OD $LD
mutate dticklong   's/d_n\[d\] == 1 \&\& now >= d_t0\[d\] + get_opt(dev, O_LONG_MS)/d_n[d] == 1 \&\& now >= d_t0[d] + 100000/' $OD $LD
mutate dnoslop     's/geom.absv(d_lx\[d\] - d_sx\[d\]) > slop/geom.absv(d_lx[d] - d_sx[d]) > 0/' $OD $LD
mutate ddragstart  's/emit(EV_DRAG_BEGIN, d_sx\[d\], d_sy\[d\], 0)/emit(EV_DRAG_BEGIN, d_lx[d], d_ly[d], 0)/' $OD $LD
mutate ddragend    's/emit(EV_DRAG_END, d_lx\[d\], d_ly\[d\], 0)/emit(EV_DRAG_END, d_sx[d], d_sy[d], 0)/' $OD $LD
mutate dtapchain   's/n = d_tap_n\[d\] + 1/n = 1/' $OD $LD
mutate ddtapwin    's/now - d_tap_t\[d\] <= get_opt(dev, O_DTAP_MS)/now - d_tap_t[d] <= 100000/' $OD $LD
mutate ddtapnear   's/geom.absv(x - d_tap_x\[d\]) <= near/true/' $OD $LD
mutate dnopalm     's/if palm != 0 \&\& size >= palm { return }//' $OD $LD
mutate dnoenabled  's/if get_opt(dev, O_ENABLED) == 0 {$/if false {/' $OD $LD
mutate dwheelsign  's/vv = 0 - qy/vv = qy/' $OD $LD
mutate dnatural    's/if get_opt(dev, O_NATURAL) != 0 {/if false {/' $OD $LD
mutate dnohscroll  's/if get_opt(dev, O_HSCROLL) != 0 { d_accx/if true { d_accx/' $OD $LD
mutate dnopinchopt 's/if get_opt(dev, O_PINCH) != 0 \&\& md > mc \* 2 {/if md > mc * 2 {/' $OD $LD
mutate dnoswipeopt 's/get_opt(dev, O_SWIPE) == 0 { return }/false { return }/' $OD $LD
mutate dswipeagain 's/^        d_phase\[d\] = P_DONE$/        d_phase[d] = P_SWIPE/' $OD $LD
mutate dnolock     's/if mc < slop \&\& md < slop {/if false {/' $OD $LD
mutate dlockloss   's/^            d_cx\[d\] = d_ax\[d\]$/            d_cx[d] = cx/' $OD $LD
mutate dpinchstep  's/var q: i64 = geom.sdiv(d_pacc\[d\], step)/var q: i64 = geom.sdiv(d_pacc[d], step * 2)/' $OD $LD
mutate dwheelstep  's/let step: i64 = opt_i(dev, O_WHEEL_PX)/let step: i64 = 20/g' $OD $LD
mutate donedev     's/let d: usize = dev as usize/let d: usize = 0/g' $OD $LD
mutate dnomaxclamp 's/if v > opt_max\[opt as usize\] { v = opt_max\[opt as usize\] }//' $OD $LD

echo "touchgest: $pass promises, $fail errors"
[ "$fail" = 0 ]
