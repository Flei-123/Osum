#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== fh7000: family 7000 legacy loader, ids, firmware names =="
if $FIRNC tools/wlan/fh8000.fi -o "$D/fh" 2> "$D/err"; then ok "flow-handler model builds against iwl_fh7000.fi"
else bad "model does not build"; head -20 "$D/err"; echo "FH7000: $pass passed, $((fail+1)) failed"; exit 1; fi
python3 -I tools/wlan/fh7000_ref.py gen "$D" || { bad "reference generator"; exit 1; }

cases=$(cd "$D" && ls d*.case | sed 's/\.case$//')
for c in $cases; do
    "$D/fh" < "$D/$c.case" > "$D/$c.out" 2>&1
    if cmp -s "$D/$c.out" "$D/$c.exp"; then ok "case $c: trace + summary == Python reference ($(wc -l < "$D/$c.exp") lines)"
    else bad "case $c differs from the reference"; diff "$D/$c.out" "$D/$c.exp" | head -6; fi
done

anchor() {
    if grep -q -- "$2" "$D/$1.out"; then ok "anchor $1: $3"; else bad "anchor $1: $3 (no match for $2)"; fi
}
anchor d1_dual 'P 0x1e7c 0x420400'                 "CPU2 header address written for a dual-CPU image"
anchor d1_dual 'LOADSTAT 0x0'                      "no secure-boot status words on family 7000"
anchor d1_dual 'W 0x20 0x0'                        "CPU reset released through CSR_RESET"
anchor d2_single 'cpu1=2 cpu2=0'                   "single-CPU image: no CPU2 header, CPU2 never loaded"
anchor d1_dual 'VIOL 0 LOST 0'                     "no protocol violation, nothing misdirected"
anchor d8_lost_irq 'RC -45'                        "lost completion interrupt -> timeout"
anchor d5_nocpu1 'RC -41'                          "no CPU1 section refused"
anchor d6_empty 'RC -43 FAILSEC 2'                 "empty section refused"
anchor d7_tiny 'RC -40'                            "bounce buffer under one page refused"
if ! grep -q '^P 0x1e7c' "$D/d2_single.out" && ! grep -q '^P 0x1e7c' "$D/d3_single_with_sep.out"; then ok "no CPU2 header write without the two-CPU flag"; else bad "CPU2 header written for a single-CPU image"; fi
if ! grep -q 'P 0x300c\|P 0xa030b4' "$D/d1_dual.out"; then ok "no 8000-family secure CPU reset / WFPM writes"; else bad "8000-family writes leaked into the 7000 path"; fi

if $FIRNC tools/wlan/iwl.fi -o "$D/iwl" 2> "$D/ierr"; then
    "$D/iwl" < /dev/null > "$D/iwl.out" 2>&1
    n7=$(grep -c '^  OK    G7' "$D/iwl.out" || true)
    f7=$(grep -c '^  FAIL  G7' "$D/iwl.out" || true)
    if [ "$n7" -ge 8 ] && [ "$f7" -eq 0 ]; then ok "id/model/firmware-name checks G7*: $n7 pass"; else bad "id/model/firmware-name checks G7*: $n7 pass, $f7 fail"; grep 'FAIL' "$D/iwl.out" | head -5; fi
else bad "tools/wlan/iwl.fi does not build"; head -10 "$D/ierr"; fi

mutate() {
    local name=$1 file=$2 expr=$3
    rm -rf "$D/m"; mkdir -p "$D/m/lib"
    for e in lib/*; do [ "$(basename "$e")" = wlan ] || ln -s "$PWD/$e" "$D/m/lib/$(basename "$e")"; done
    cp -r lib/wlan "$D/m/lib/wlan"
    if ! sed -i "$expr" "$D/m/lib/wlan/$file" || cmp -s "lib/wlan/$file" "$D/m/lib/wlan/$file"; then bad "mutation $name: sed did not change the file"; return; fi
    if ! FIRNLIB="$D/m/lib" $FIRNC tools/wlan/fh8000.fi -o "$D/mfh" 2> "$D/merr"; then bad "mutation $name: mutant does not build"; head -3 "$D/merr"; return; fi
    local caught=0
    for c in $cases; do
        if ! "$D/mfh" < "$D/$c.case" 2>&1 | cmp -s - "$D/$c.exp"; then caught=1; break; fi
    done
    rm -f "$D/mfh"
    if [ $caught -eq 1 ]; then ok "mutation $name caught"; else bad "mutation $name NOT caught"; fi
}
mutate "CPU2 header address wrong"            iwl_fh7000.fi 's/const CPU2_HDR_ADDR: u64 = 0x1E7C/const CPU2_HDR_ADDR: u64 = 0x1E78/'
mutate "CPU2 header space wrong"              iwl_fh7000.fi 's/0x420400/0x420000/'
mutate "CPU reset never released"             iwl_fh7000.fi '/RESET_RELEASE)$/d'
mutate "CPU reset value wrong"                iwl_fh7000.fi 's/const RESET_RELEASE: u64 = 0/const RESET_RELEASE: u64 = 1/'
mutate "interrupt mask not restored"          iwl_fh7000.fi '/INT_INI_SET_MASK)$/d'
mutate "CPU2 loaded without the two-CPU flag" iwl_fh7000.fi 's/(\*f).num_cpu == DUAL_CPU/true/'
mutate "CPU2 never loaded"                    iwl_fh7000.fi 's/(\*f).num_cpu == DUAL_CPU/false/'
mutate "RF-kill handshake bits not cleared"   iwl_fh7000.fi '/SW_BIT_RFKILL)$/d'
mutate "FH-only interrupt mask skipped"       iwl_fh7000.fi 's/iwl_fh8000.wr(p, iwl_pwr.CSR_INT_MASK, iwl_fh8000.INT_FH_TX)//'
mutate "empty section accepted"               iwl_fh7000.fi 's/return iwl_fh8000.E_FH_EMPTY/i = i + 0/'
mutate "bounce buffer size not checked"       iwl_fh7000.fi 's/if bsize < 4096 { return iwl_fh8000.E_FH_BOUNCE }//'
mutate "chunk plan ignores the bounce buffer" iwl_fh8000.fi 's/if c > bsize { c = bsize }//'

echo "FH7000: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
