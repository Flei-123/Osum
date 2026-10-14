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

# negative controls: break one rule at a time in a copy of the lib
mutate() { # name sed-expression
    local name=$1 expr=$2
    local L="$T/lib-$name"
    mkdir -p "$L"
    for d in lib/*; do
        [ "$(basename "$d")" = touchgest ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    mkdir -p "$L/touchgest"
    sed -e "$expr" lib/touchgest/gest.fi > "$L/touchgest/gest.fi"
    if cmp -s lib/touchgest/gest.fi "$L/touchgest/gest.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/touchgest/oracle.fi -o "$T/o-$name" 2>/dev/null; then
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
mutate noslop      's/if absv(x - c_lx\[k\]) + absv(y - c_ly\[k\]) > sl2 {/if absv(x - c_lx[k]) + absv(y - c_ly[k]) > 0 {/'
mutate nopinch     's/if dd > tr {/if false {/'
mutate swipeagain  's/if d_fired\[d\] == 0 {/if true {/'
mutate noedge      's/if c_edge\[k\] == 1 {/if false {/'
mutate rightclick  's/emit(EV_CLICK, 2, 0)/emit(EV_CLICK, 1, 0)/'
mutate nobutton    's/d_btn\[d\] == 0 \&\&//'
mutate onedev      's/let d: usize = dev as usize/let d: usize = 0/g'

echo "touchgest: $pass promises, $fail errors"
[ "$fail" = 0 ]
