#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
printf 'import bt.hci\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" && ok "lib compiles with --profile=kernel" || { bad "lib does not compile"; head -5 "$T/k.err"; }
for orc in oracle oracle_le; do
"$FIRNC" tools/bt/$orc.fi -o "$T/$orc" 2> "$T/o.err" && ok "$orc builds" || { bad "$orc does not build"; head -10 "$T/o.err"; }
if [ -x "$T/$orc" ]; then
    timeout 60 "$T/$orc" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n "s/^FAIL /  FAIL  $orc: /p" "$T/out.txt"
    [ "$rc" = 0 ] && ok "$orc exits 0" || bad "$orc exit code $rc"
    [ "$nbad" = 0 ] && ok "$orc: no FAIL line" || bad "$orc: $nbad FAIL lines"
    [ "$nok" -ge 15 ] && ok "$orc: $nok promises OK (>= 15)" || bad "$orc: only $nok OK"
    pass=$((pass+nok))
fi
done
mutate() {
    local name=$1 file=$2 expr=$3 orc=${4:-oracle}
    local L="$T/lib-$name"
    mkdir -p "$L/bt"
    for d in lib/*; do
        [ "$(basename "$d")" = bt ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    for f in lib/bt/*.fi; do cp "$f" "$L/bt/"; done
    sed -i -e "$expr" "$L/bt/$file.fi"
    if cmp -s "lib/bt/$file.fi" "$L/bt/$file.fi"; then bad "control $name: mutation changed nothing"; return; fi
    if ! FIRNLIB="$L" "$FIRNC" tools/bt/$orc.fi -o "$T/o-$name" 2>/dev/null; then bad "control $name: mutated oracle does not build"; return; fi
    local out nf rc
    out=$(timeout 20 "$T/o-$name" 2>&1)
    rc=$?
    nf=$(printf '%s\n' "$out" | grep -c '^FAIL')
    if [ "$nf" -gt 0 ] || [ "$rc" != 0 ]; then ok "control $name: oracle goes red (FAIL=$nf rc=$rc)"; else bad "control $name: oracle stays green on a broken lib"; fi
}
mutate count_bound hci 's/return plen >= 1 \&\& 1 + inq_count(ev) \* ENTRY_LEN <= plen/return true/'
mutate dedupe      hci 's/var idx: u64 = tab_find(tab, addr)/var idx: u64 = 0xFFFFFFFF/'
mutate addr_order  hci 's/let b: u64 = octets.ld8(addr, i)/let b: u64 = octets.ld8(addr, 5 - i)/'
mutate cap         hci 's/if n >= cap {/if false {/'
mutate rssi_sign   hci 's/return (v as i64) - 256/return v as i64/'
mutate cod_clobber hci 's/octets.st8(r, REC_COD + 2, cod >> 16)/octets.st32(r, REC_COD + 2, cod >> 16)/' oracle_le
mutate le_bound    ble 's/return 4 + 10 \* n + data_total(ev, n) <= 2 + hci.event_plen(ev)/return true/' oracle_le
mutate le_layout   ble 's/return ev + 4 + 2 \* report_count(ev) + 6 \* i/return ev + 4 + 2 * report_count(ev) + 6 * 0/' oracle_le
mutate le_rssi_at  ble 's/return octets.ld8(ev, 4 + 9 \* n + data_total(ev, n) + i)/return octets.ld8(ev, 4 + 9 * n + data_total(ev, n))/' oracle_le
mutate conn_mask   ble 's/return octets.ld16(ev, 4) \& HANDLE_MASK/return octets.ld16(ev, 4)/' oracle_le
mutate parse_order  ble 's/octets.st8(dst, 5 - k, hi \* 16 + lo)/octets.st8(dst, k, hi * 16 + lo)/' oracle_le
mutate le_flags    ble 's/flags = flags | hci.FLAG_RANDOM/flags = flags/' oracle_le
mutate le_uuid     ble 's/if octets.ld16(data, at + 2 + 2 \* k) == uuid {/if octets.ld16(data, at + 2) == uuid {/' oracle_le
printf '\nBT: %d ok, %d fail\n' "$pass" "$fail"
[ "$fail" = 0 ]
