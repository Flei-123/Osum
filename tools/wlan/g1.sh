#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
echo "== g1: gen1 ring + scheduler register programs =="
python3 -I tools/wlan/g1_ref.py > "$D/exp"
if $FIRNC tools/wlan/g1.fi -o "$D/g1" 2> "$D/err"; then ok "tools/wlan/g1.fi builds"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
"$D/g1" > "$D/out"
if cmp -s "$D/out" "$D/exp"; then ok "register programs (rx init, tx init, scheduler, queue enable, doorbells) == reference ($(wc -l < "$D/exp") writes)"; else bad "programs differ"; diff "$D/out" "$D/exp" | head -10; fi
mut() {
    rm -rf "$D/m"; mkdir -p "$D/m"; cp -r lib/. "$D/m/"
    sed -i "$1" "$D/m/wlan/iwl_g1.fi"
    if FIRNLIB="$D/m" $FIRNC tools/wlan/g1.fi -o "$D/mm" 2> /dev/null && "$D/mm" > "$D/mo" 2>/dev/null && ! cmp -s "$D/mo" "$D/exp"; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
}
mut 's/const FH_RSCSR_RBDCB_BASE: u64 = 0x1BC4/const FH_RSCSR_RBDCB_BASE: u64 = 0x1BC8/' "RBD base register"
mut 's/bd_bus >> 8)/bd_bus >> 4)/' "RBD base shift"
mut 's/(RX_RB_TIMEOUT << 4)/(RX_RB_TIMEOUT << 5)/' "RX config timeout position"
mut 's/bc_bus >> 10/bc_bus >> 8/' "scheduler byte-count table shift"
mut 's/restocked \& 0xFFF8/restocked/' "RX write pointer multiple of 8"
mut 's/add(g, K_DIRECT, FH_RCSR_FLUSH_RB_REQ, 0)/add(g, K_DIRECT, FH_RCSR_FLUSH_RB_REQ, 1)/' "flush request cleared in RX init"
mut 's/const FH_RSCSR_RDPTR: u64 = 0x1BCC/const FH_RSCSR_RDPTR: u64 = 0x1BC8/' "RX read pointer register"
mut 's/FH_RCSR_RBDCB_WPTR: u64 = 0x1C08/FH_RCSR_RBDCB_WPTR: u64 = 0x1C0C/' "RCSR write pointer register"
mut 's/add(g, K_CSR8, CSR_INT_COALESCING/add(g, K_CSR, CSR_INT_COALESCING/' "coalescing byte write kind"
mut 's/(iwl_pwr.rd(p, a) \& 0xFFFFFF00) | (v \& 0xFF)/v/' "coalescing read-modify-write keeps other bytes"
mut 's/ok = ok && add(g, K_PRPH, SCD_EN_CTRL, 1 << q)/ok = ok/' "scheduler enable of the command queue (SCD_EN_CTRL)"
mut 's/add(g, K_PRPH, scd_status_reg(q), SCD_STTS_ACT_EN)/add(g, K_PRPH, scd_status_reg(q), 0)/' "queue set inactive before configuring"
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
