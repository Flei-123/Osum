#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/backlum-host/run.sh -- host test of lib/fui/backlum.fi (luminance table, contrast, text colour decider with hysteresis + hold, scrim)
# plus MUTATIONS: each mutated copy of the lib must turn tools/backlum-host/host.fi red. No QEMU, seconds.
#   bash tools/backlum-host/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

build_run() { # libdir out -> exit code of the test, output in $2.txt
    FIRNLIB="$1" vendor/firn/bin/firnc --profile=app tools/backlum-host/host.fi -o "$2" > "$2.build" 2>&1 || return 99
    "$2" > "$2.txt"
}

build_run "$PWD/lib" "$T/real"; rc=$?
if [ "$rc" = 0 ]; then ok "host test green ($(tail -1 "$T/real.txt"))"; else bad "host test rc=$rc"; grep -v '^warning' "$T/real.build" | head; grep '^FAIL' "$T/real.txt" | head; fi

cat > "$T/kcheck.fi" <<'KEOF'
profile kernel
import fui.backlum
export { u_start }
fn u_start(args: u64) -> u64 {
    return backlum.lum_q16(args) + backlum.tc_update(args, 0, 0)
}
KEOF
if FIRNLIB="$PWD/lib" vendor/firn/bin/firnc --profile=kernel -c "$T/kcheck.fi" -o "$T/kcheck.o" > "$T/kcheck.build" 2>&1; then
    ok "fui.backlum compiles in profile kernel"
else
    bad "fui.backlum does not compile in profile kernel"; grep -v '^warning' "$T/kcheck.build" | head
fi

mutate() { # name old new
    local d="$T/m_$1"
    rm -rf "$d"; mkdir -p "$d"; cp -r lib "$d/lib"
    python3 - "$d/lib/fui/backlum.fi" "$2" "$3" <<'PYEOF'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    print("MUTATION-ANCHOR-MISSING"); sys.exit(2)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
    [ "$?" = 0 ] || { bad "mutation $1: anchor missing (the lib changed, update this script)"; return; }
    build_run "$d/lib" "$d/t"; local r=$?
    if [ "$r" != 0 ] && [ "$r" != 99 ]; then ok "mutation '$1' is caught ($(grep -c '^FAIL' "$d/t.txt") red)"
    elif [ "$r" = 99 ]; then bad "mutation '$1' does not even compile"
    else bad "mutation '$1' SURVIVED (test stays green)"; fi
}
mutate switch-point-half "const L_SWITCH: u64 = 11731" "const L_SWITCH: u64 = 32768"
mutate switch-point-low "const L_SWITCH: u64 = 11731" "const L_SWITCH: u64 = 5000"
mutate no-band "if cur == TXT_WHITE && lum > L_SWITCH + band {" "if cur == TXT_WHITE && lum > L_SWITCH {"
mutate no-band-down "if cur == TXT_BLACK && lum + band < L_SWITCH {" "if cur == TXT_BLACK && lum < L_SWITCH {"
mutate no-hold "if want != cur && now_ms - tget(st, 1) >= hold {" "if want != cur {"
mutate hold-off-by-one "now_ms - tget(st, 1) >= hold" "now_ms - tget(st, 1) > hold"
mutate no-flip-count "tput(st, 2, tget(st, 2) + 1)" "tput(st, 2, tget(st, 2))"
mutate no-time-update "        tput(st, 1, now_ms)
        tput(st, 2, tget(st, 2) + 1)" "        tput(st, 2, tget(st, 2) + 1)"
mutate gamma-linear "return LIN[(c & 0xFF) as usize] as u64" "return (c & 0xFF) * 257"
mutate weight-green "return (r * 2126 + g * 7152 + b * 722) / 10000" "return (r * 3333 + g * 3333 + b * 3333) / 10000"
mutate weight-swap "return (r * 2126 + g * 7152 + b * 722) / 10000" "return (b * 2126 + g * 7152 + r * 722) / 10000"
mutate contrast-no-offset "return ((hi + HALF_OF_FIVE) * 100) / (lo + HALF_OF_FIVE)" "return (hi * 100) / (lo + 1)"
mutate contrast-asym "    var hi: u64 = l1
    var lo: u64 = l2
    if lo > hi {
        hi = l2
        lo = l1
    }" "    var hi: u64 = l1
    var lo: u64 = l2"
mutate init-no-decide "tput(st, 0, text_for(lum))" "tput(st, 0, TXT_WHITE)"
mutate scrim-none "        return 255 - (12012 * 255) / hi" "        return 0"
mutate scrim-black-weak "    return ((11469 - lo) * 255) / (65536 - lo) + 1" "    return ((11469 - lo) * 255) / (65536 - lo) / 2"
mutate tie-to-black "    if lum > L_SWITCH {
        return TXT_BLACK
    }
    return TXT_WHITE" "    if lum >= L_SWITCH {
        return TXT_BLACK
    }
    return TXT_WHITE"
echo
echo "backlum-host: OK=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
