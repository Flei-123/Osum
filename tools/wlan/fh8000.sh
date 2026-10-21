#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/fh8000.sh -- gate for lib/wlan/iwl_fh8000.fi (HP-9a: Intel family 8000 FH chunk loader).
#
# Host-only (QEMU has no Intel WLAN device). The REAL library runs against a flow-handler model
# (tools/wlan/fh8000.fi: MAC access windows, channel-9 write order, DMA from a host window into SRAM,
# LMPM_CHICK extended range). Every case's output (register-write trace + summary) is compared with an
# independent Python reference that follows the Linux loader literally (tools/wlan/fh8000_ref.py), plus
# hard-coded anchors for the chunk arithmetic, plus broken-library controls.
#
# usage: bash tools/wlan/fh8000.sh        exit 0 = all OK
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== fh8000: family 8000 chunk loader =="
if $FIRNC tools/wlan/fh8000.fi -o "$D/fh" 2> "$D/err"; then ok "tools/wlan/fh8000.fi builds against lib/wlan/iwl_fh8000.fi"
else bad "fh8000.fi does not build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$((fail))"; exit 1; fi
python3 -I tools/wlan/fh8000_ref.py gen "$D" || { bad "reference generator"; exit 1; }

cases=$(cd "$D" && ls *.case | sed 's/\.case$//')
for c in $cases; do
    "$D/fh" < "$D/$c.case" > "$D/$c.out" 2>&1
    if cmp -s "$D/$c.out" "$D/$c.exp"; then ok "case $c: trace + summary == Python reference ($(wc -l < "$D/$c.exp") lines)"
    else bad "case $c differs from the reference"; diff "$D/$c.out" "$D/$c.exp" | head -6; fi
done

anchor() { # case grep-pattern description
    if grep -q -- "$2" "$D/$1.out"; then ok "anchor $1: $3"; else bad "anchor $1: $3 (no match for $2)"; fi
}
anchor c1_big   'STAT chunks=6 bytes=151461 ext=2 cpu1=3 cpu2=2' "6 chunks (0x20001 splits in two), 2 extended-range chunks (0x40000, 0x57000)"
anchor c1_big   'LOADSTAT 0xffffffff'                           "CPU2 completion word last"
anchor c1_big   'VIOL 0 LOST 0 NONZERO 151461'                   "no protocol violation, nothing misdirected, paging section not loaded"
anchor c1_page  'STAT chunks=40 bytes=151461 ext=2'              "4096-octet bounce buffer: 40 chunks, extended range decided per chunk start"
anchor c1_hi15  'VIOL 0 LOST 0'                                  "bus address bits 32..35 reach CTRL1 (hi = 15)"
anchor c2_exact 'STAT chunks=4 bytes=524288 ext=0 cpu1=2 cpu2=1' "exact multiples of 0x20000 make no extra chunk"
anchor cb_bigbuf 'STAT chunks=4 bytes=524288 ext=0' "buffer above 0x20000: chunks still capped at 0x20000 (1 + 1 + 2)"
anchor cc_edges 'STAT chunks=5 bytes=22 ext=3' "extended range is 0x40000..0x57FFF inclusive (0x3FFFF/0x58000 out, 0x40000/0x57FFE/0x57FFF in)"
anchor c3_single 'RC 0 FAILSEC 0'                                "image without separators loads, CPU2 loop empty"
anchor c3_single 'LOADSTAT 0xffffffff'                           "... and still writes the CPU2 completion word"
anchor c4_16    'cpu1=16 cpu2=1'                                 "16 sections per CPU are accepted"
anchor c5_17    'RC -42 FAILSEC 0'                               "17 sections for one CPU refused before any write"
anchor c6_empty 'RC -43 FAILSEC 2'                               "empty section refused, reported by section index"
anchor c7_nocpu1 'RC -41'                                        "no CPU1 section refused"
anchor c9_tiny  'RC -40'                                         "bounce buffer under one page refused"
anchor c8_lost_irq 'RC -45 FAILSEC 0'                            "lost completion interrupt -> timeout, section reported"
anchor c8_lost_ext 'CHICK 0x0'                                   "... extended-range bit cleared again on the error path"
anchor c5_17    'NONZERO 0 '                                     "refused image wrote nothing to SRAM"

# ---- counter-probes: one mutation each; at least one case must differ from the reference ----
mutate() { # name sed-expr
    local name=$1 expr=$2
    rm -rf "$D/m"; mkdir -p "$D/m/lib"
    for e in lib/*; do [ "$(basename "$e")" = wlan ] || ln -s "$PWD/$e" "$D/m/lib/$(basename "$e")"; done
    cp -r lib/wlan "$D/m/lib/wlan"
    if ! sed -i "$expr" "$D/m/lib/wlan/iwl_fh8000.fi" || cmp -s lib/wlan/iwl_fh8000.fi "$D/m/lib/wlan/iwl_fh8000.fi"; then bad "mutation $name: sed did not change the file"; return; fi
    if ! FIRNLIB="$D/m/lib" $FIRNC tools/wlan/fh8000.fi -o "$D/mfh" 2> "$D/merr"; then bad "mutation $name: mutant does not build"; head -3 "$D/merr"; return; fi
    local caught=0
    for c in $cases; do
        if ! "$D/mfh" < "$D/$c.case" 2>&1 | cmp -s - "$D/$c.exp"; then caught=1; break; fi
    done
    rm -f "$D/mfh"
    if [ $caught -eq 1 ]; then ok "mutation $name caught"; else bad "mutation $name NOT caught"; fi
}
mutate "CPU2 status bits shifted by 8, not 16"          's/if cpu == 2 { v = v << 16 }/if cpu == 2 { v = v << 8 }/'
mutate "chunk size ignores the 0x20000 limit"           's/if c > FH_MAX_CHUNK { c = FH_MAX_CHUNK }//'
mutate "chunk size ignores the bounce buffer"           's/if c > bsize { c = bsize }//'
mutate "extended range end is exclusive"                's/dst <= FH_EXT_END/dst < FH_EXT_END/'
mutate "extended range never recognised"                's/let ext: bool = fh_is_ext(dst)/let ext: bool = false/'
mutate "LMPM_CHICK bit left set after the chunk"        's/prph_bits(p, LMPM_CHICK, 1, false)/prph_bits(p, LMPM_CHICK, 0, false)/'
mutate "bus address bits 32..35 dropped"                's/return (phys >> 32) \& 0xF/return 0/'
mutate "buffer-valid word never written"                's/wr(p, FH_TCSR_BUFSTS9, BUFSTS_VALID)//'
mutate "channel never paused before reprogramming"      's/wr(p, FH_TCSR_CONFIG9, CFG_PAUSE)//'
mutate "chunk run without MAC access"                   '/^fn push_chunk/,/^}/ s/if iwl_pwr.mac_access_get(p) != 0 {/if false {/'
mutate "load status overwritten, no MAC access"         's/let r2: i64 = direct_or(p, FH_UCODE_LOAD_STATUS, fh_status_bits(k, cpu))/wr(p, FH_UCODE_LOAD_STATUS, fh_status_bits(k, cpu)); let r2: i64 = 0/'
mutate "CPU1 completion word wrong"                     's/direct_wr(p, FH_UCODE_LOAD_STATUS, 0xFFFF)/direct_wr(p, FH_UCODE_LOAD_STATUS, 0xFFFFFFFF)/'
mutate "lost completion interrupt ignored"              's/if !poll_int_tx(p) { return E_FH_TIMEOUT }//'
mutate "completion not acknowledged in FH_INT"          's/wr(p, iwl_pwr.CSR_FH_INT_STATUS, FH_INT_TX_MASK)//'
mutate "more than 16 sections per CPU accepted"         's/iwl_fw.KIND_LMAC) > FH_CPU_MAX/iwl_fw.KIND_LMAC) > 99/'
mutate "paging sections loaded as CPU2"                 's/if cpu == 2 { want = iwl_fw.KIND_UMAC }/if cpu == 2 { want = iwl_fw.KIND_PAGING }/'
mutate "WFPM_GP2 default value wrong"                   's/0x01010101)/0x01010100)/'
mutate "RF-kill handshake bits not cleared"             's/wr(p, CSR_UCODE_DRV_GP1_CLR, SW_BIT_RFKILL)//'
mutate "empty section accepted"                         's/return E_FH_EMPTY/let _x: u64 = 0/'
mutate "CPU reset never released"                       's/r = prph_w(p, RELEASE_CPU_RESET, 0x01000000)/r = 0/'
mutate "interrupt mask not restored after a CPU"        's/wr(p, iwl_pwr.CSR_INT_MASK, INT_INI_SET_MASK)//'

echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
