#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
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
printf 'import bt.hci\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" && ok "lib compiles with --profile=kernel" || { bad "lib does not compile"; head -5 "$T/k.err"; }
"$FIRNC" tools/bt/oracle.fi -o "$T/oracle" 2> "$T/o.err" && ok "oracle builds" || { bad "oracle does not build"; head -10 "$T/o.err"; }
if [ -x "$T/oracle" ]; then
    timeout 60 "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 15 ] && ok "oracle: $nok promises OK (>= 15)" || bad "oracle: only $nok OK"
    pass=$((pass+nok))
fi
mutate() {
    local name=$1 expr=$2
    local L="$T/lib-$name"
    mkdir -p "$L/bt"
    for d in lib/*; do
        [ "$(basename "$d")" = bt ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    sed -e "$expr" lib/bt/hci.fi > "$L/bt/hci.fi"
    if cmp -s lib/bt/hci.fi "$L/bt/hci.fi"; then bad "control $name: mutation changed nothing"; return; fi
    if ! FIRNLIB="$L" "$FIRNC" tools/bt/oracle.fi -o "$T/o-$name" 2>/dev/null; then bad "control $name: mutated oracle does not build"; return; fi
    local out nf rc
    out=$(timeout 20 "$T/o-$name" 2>&1)
    rc=$?
    nf=$(printf '%s\n' "$out" | grep -c '^FAIL')
    if [ "$nf" -gt 0 ] || [ "$rc" != 0 ]; then ok "control $name: oracle goes red (FAIL=$nf rc=$rc)"; else bad "control $name: oracle stays green on a broken lib"; fi
}
mutate count_bound 's/return plen >= 1 \&\& 1 + inq_count(ev) \* ENTRY_LEN <= plen/return true/'
mutate dedupe      's/var idx: u64 = tab_find(tab, addr)/var idx: u64 = 0xFFFFFFFF/'
mutate addr_order  's/let b: u64 = le.ld8(addr, i)/let b: u64 = le.ld8(addr, 5 - i)/'
mutate cap         's/if n >= cap {/if false {/'
mutate rssi_sign   's/return (v as i64) - 256/return v as i64/'
printf '\nBT: %d ok, %d fail\n' "$pass" "$fail"
[ "$fail" = 0 ]
