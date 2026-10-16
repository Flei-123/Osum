#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/iwlm2.sh -- gate for W-AX201 M2/M3 prep (no hardware, no QEMU):
#   lib/wlan/iwl_fw.fi   TLV parser + section split   vs an independent Python parser (iwlfw_ref.py)
#   lib/wlan/iwl_pwr.fi  reset/clock/PRPH/fw-kick      vs a CSR model with real handshakes (iwlpwr.fi)
#   lib/wlan/iwl_ctxt.fi context info, TFD, command queue (round trips, bounds, layout table)
#   lib/wlan/scanfmt.fi  scan results as text lines (real beacons from tools/wlan/mitschnitt.txt)
# Plus 9 counter-probes: each mutates ONE line of a copy of lib/wlan and must turn the gate red.
# With WLAN_AX201_FW=<real .ucode> the real blob is parsed too and compared with the Python walk.
# usage: bash tools/wlan/iwlm2.sh        exit 0 = all OK
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== iwl M2/M3 prep: firmware sections, power sequence, context info, queues =="
python3 -I tools/wlan/iwlfw_ref.py gen "$D" || { bad "blob generator"; echo "RESULT pass=$pass fail=$fail"; exit 1; }
if $FIRNC tools/wlan/iwlfw.fi -o "$D/fw" 2> "$D/e1"; then ok "iwlfw.fi builds"; else bad "iwlfw.fi build"; head -10 "$D/e1"; fi
if $FIRNC tools/wlan/iwlpwr.fi -o "$D/pw" 2> "$D/e2"; then ok "iwlpwr.fi builds"; else bad "iwlpwr.fi build"; head -10 "$D/e2"; fi

# expected return codes for the hostile blobs (the reference parser is independent of the Firn code)
declare -A RC=([good]=0 [edge_32]=0 [bad_trunc]=-11 [bad_len]=-11 [bad_magic]=-10 [bad_short]=-10 [bad_secshort]=-12 [bad_nort]=-13 [bad_toomany]=-12)
if [ -x "$D/fw" ]; then
    for n in "${!RC[@]}"; do
        "$D/fw" < "$D/$n.bin" > "$D/o_fw" 2>&1; python3 -I tools/wlan/iwlfw_ref.py parse "$D/$n.bin" > "$D/o_py"
        if cmp -s "$D/o_fw" "$D/o_py" && [ "$(head -1 "$D/o_fw")" = "RC ${RC[$n]}" ]; then ok "fw $n: Firn == Python, RC ${RC[$n]}"
        else bad "fw $n: Firn vs Python differ or wrong RC"; diff "$D/o_fw" "$D/o_py" | head -4; fi
    done
    c=$(grep -c '^SEC 0 .* kind=0 ' "$D/o_fw" || true)
    "$D/fw" < "$D/good.bin" | grep -q 'SUM ver=77 tlv=23 flags=17 sku=68 cpu=2 api0=21 capa0=3 paging=32768' && ok "good.bin summary (api0 ORs index-0 TLVs only, index 1 ignored)" || bad "good.bin summary"
    "$D/fw" < "$D/good.bin" | awk '/^SEC 0/{k[$4]++} END{exit !(k["kind=0"]==2 && k["kind=1"]==3 && k["kind=2"]==2)}' && ok "good.bin RT split 2 lmac / 3 umac / 2 paging" || bad "good.bin RT split"
    if [ -n "${WLAN_AX201_FW:-}" ] && [ -f "$WLAN_AX201_FW" ]; then
        "$D/fw" < "$WLAN_AX201_FW" > "$D/o_fw" 2>&1; python3 -I tools/wlan/iwlfw_ref.py parse "$WLAN_AX201_FW" > "$D/o_py"
        if cmp -s "$D/o_fw" "$D/o_py" && [ "$(head -1 "$D/o_fw")" = "RC 0" ]; then ok "REAL ucode: Firn == Python ($(sed -n 2p "$D/o_fw"))"
        else bad "REAL ucode: Firn vs Python differ"; diff "$D/o_fw" "$D/o_py" | head -4; fi
    else
        echo "  (no WLAN_AX201_FW: real-blob check skipped; TLV numbers stay unconfirmed against Intel's file)"
    fi
fi
if [ -x "$D/pw" ]; then
    "$D/pw" < "$D/good.bin" > "$D/o_pw"; rc=$?
    grep -v '^  OK' "$D/o_pw" | head -20
    p=$(grep -c '^  OK    ' "$D/o_pw" || true); f=$(grep -c '^  FAIL  ' "$D/o_pw" || true)
    [ $rc -eq 0 ] && [ "$f" -eq 0 ] && [ "$p" -ge 57 ] && ok "iwlpwr: $p checks green (model + ctxt + queues)" || bad "iwlpwr: $p ok / $f fail rc=$rc"
fi

# ---- scan result lines (chip independent, /proc/wlan material) ----
if python3 -I tools/wlan/scanfmt_ref.py tools/wlan/mitschnitt.txt "$D/sf_in.txt" "$D/sf_exp.txt" && $FIRNC tools/wlan/scanfmt.fi -o "$D/sf" 2> "$D/e3"; then
    "$D/sf" < "$D/sf_in.txt" > "$D/sf_out.txt"
    if cmp -s "$D/sf_out.txt" "$D/sf_exp.txt"; then ok "scanfmt: real beacons + open/WEP/hidden/duplicate/truncated -> expected lines"; else bad "scanfmt output differs"; diff "$D/sf_out.txt" "$D/sf_exp.txt" | head -6; fi
    grep -q '^Caf?E?x ch=6 sec=open rssi=-40$' "$D/sf_out.txt" && [ "$(wc -l < "$D/sf_out.txt")" -eq 3 ] && ok "scanfmt: hostile SSID cannot forge a line or field (3 networks = 3 lines)" || bad "scanfmt sanitising"
    { echo "cap 60"; cat "$D/sf_in.txt"; } | "$D/sf" > "$D/sf_cap.txt"
    [ "$(cat "$D/sf_cap.txt")" = "$(head -1 "$D/sf_exp.txt")" ] && [ "$(wc -c < "$D/sf_cap.txt")" -le 60 ] && ok "scanfmt: cap 60 -> whole lines only, never past the cap" || bad "scanfmt cap"
    { echo "cap 0"; cat "$D/sf_in.txt"; } | "$D/sf" > "$D/sf_cap0.txt"
    [ ! -s "$D/sf_cap0.txt" ] && ok "scanfmt: cap 0 -> nothing written" || bad "scanfmt cap 0"
else bad "scanfmt build/input"; head -10 "$D/e3" 2>/dev/null; fi

# ---- counter-probes: one mutation each, the gate must catch it ----
mutate() { # name file sed-expr runner(fw|pw)
    local name=$1 file=$2 expr=$3 run=$4
    rm -rf "$D/m"; mkdir -p "$D/m/lib"
    for e in lib/*; do [ "$(basename "$e")" = wlan ] || ln -s "$PWD/$e" "$D/m/lib/$(basename "$e")"; done
    cp -r lib/wlan "$D/m/lib/wlan"
    if ! sed -i "$expr" "$D/m/lib/wlan/$file" || cmp -s "lib/wlan/$file" "$D/m/lib/wlan/$file"; then bad "mutation $name: sed did not change the file"; return; fi
    if [ "$run" = fw ]; then
        FIRNLIB="$D/m/lib" $FIRNC tools/wlan/iwlfw.fi -o "$D/mfw" 2> /dev/null
        "$D/mfw" < "$D/good.bin" > "$D/o_m" 2>&1; python3 -I tools/wlan/iwlfw_ref.py parse "$D/good.bin" > "$D/o_py"
        if cmp -s "$D/o_m" "$D/o_py"; then bad "mutation $name NOT caught"; else ok "mutation $name caught"; fi
    elif [ "$run" = sf ]; then
        FIRNLIB="$D/m/lib" $FIRNC tools/wlan/scanfmt.fi -o "$D/msf" 2> /dev/null
        if [ -x "$D/msf" ] && "$D/msf" < "$D/sf_in.txt" 2>&1 | cmp -s - "$D/sf_exp.txt"; then bad "mutation $name NOT caught"; else ok "mutation $name caught"; fi
        rm -f "$D/msf"
    else
        FIRNLIB="$D/m/lib" $FIRNC tools/wlan/iwlpwr.fi -o "$D/mpw" 2> /dev/null
        if [ -x "$D/mpw" ] && "$D/mpw" < "$D/good.bin" > "$D/o_m" 2>&1; then bad "mutation $name NOT caught"; else ok "mutation $name caught"; fi
        rm -f "$D/mpw"
    fi
}
mutate "apm_init never sets INIT_DONE"       iwl_pwr.fi  '/^fn apm_init/,/^}/ s/set_bits(p, iwl_probe.CSR_GP_CNTRL, GP_INIT_DONE)/let _x: u64 = 0/' pw
mutate "stop_master ignores MASTER_DISABLED"  iwl_pwr.fi  's/if !poll(p, iwl_probe.CSR_RESET, RESET_MASTER_DISABLED, RESET_MASTER_DISABLED) { return E_PWR_MASTER }//' pw
mutate "mac access ignores GOING_TO_SLEEP"    iwl_pwr.fi  's/GP_CLOCK_READY | GP_SLEEP, GP_CLOCK_READY/GP_CLOCK_READY, GP_CLOCK_READY/' pw
mutate "fw_kick skips mac access"             iwl_pwr.fi  '/^fn fw_kick/,/^}/ s/let r: i64 = mac_access_get(p)/let r: i64 = 0/' pw
mutate "txq may fill the last slot"           iwl_ctxt.fi 's/return (\*q).n - 1 - txq_used(q)/return (*q).n - txq_used(q)/' pw
mutate "context info size word wrong"         iwl_ctxt.fi 's/st16(buf, 4, (CTXT_SIZE \/ 4) as u64)/st16(buf, 4, (CTXT_SIZE \/ 8) as u64)/' pw
mutate "TFD accepts 4096-octet buffers"       iwl_ctxt.fi 's/len >= 4096/len > 4096/' pw
mutate "section classifier: separators swapped" iwl_fw.fi 's/^const SEP_CPU: u64 = 0xFFFFCCCC/const SEP_CPU: u64 = 0xAAAABBBB/;s/^const SEP_PAGING: u64 = 0xAAAABBBB/const SEP_PAGING: u64 = 0xFFFFCCCC/' fw
mutate "scanfmt lets control octets through"  scanfmt.fi  's/if c < 0x21 || c > 0x7E { c = 63 }//' sf

echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
