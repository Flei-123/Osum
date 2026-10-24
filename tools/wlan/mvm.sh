#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/mvm.sh -- gate for lib/wlan/iwl_mvm.fi (HP-9c.3 MVM command encoders): every command byte-equal to an
# independent struct.pack reference (tools/wlan/mvm_ref.py), plus 3 mutants that MUST differ.
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
echo "== mvm: command encoders =="
python3 -I tools/wlan/mvm_ref.py > "$D/exp"
if $FIRNC tools/wlan/mvm.fi -o "$D/mvm" 2> "$D/err"; then ok "tools/wlan/mvm.fi builds"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
"$D/mvm" > "$D/out"
while read -r name hex; do
    got=$(grep "^$name " "$D/out" | cut -d' ' -f2)
    if [ "$got" = "$hex" ]; then ok "command $name == reference ($((${#hex}/2)) octets)"; else bad "command $name differs"; echo "   got $got"; echo "   exp $hex"; fi
done < "$D/exp"
mut() { # sed-expr description [module]
    local mod=${3:-iwl_mvm.fi}
    mkdir -p "$D/m/wlan" && cp lib/wlan/*.fi "$D/m/wlan/" 2>/dev/null
    cp -r lib/. "$D/m/" 2>/dev/null; sed -i "$1" "$D/m/wlan/$mod"
    if FIRNLIB="$D/m" $FIRNC tools/wlan/mvm.fi -o "$D/mm" 2> /dev/null && "$D/mm" > "$D/mo" 2>/dev/null && ! cmp -s "$D/mo" "$D/out"; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
}
mut 's/const CMD_NVM_ACCESS: u64 = 0x88/const CMD_NVM_ACCESS: u64 = 0x89/' "NVM command id"
mut 's/st32(a, HDR + 4, mac_id_color)/st32(a, HDR + 8, mac_id_color)/' "ADD_STA mac_id_n_color offset"
mut 's/var fl: u64 = 2 |/var fl: u64 = 3 |/' "CCMP cipher flag"
mut 's/iwl_le.st32(a, h + 8, mac_type)/iwl_le.st32(a, h + 12, mac_type)/' "MAC_CONTEXT mac_type offset" iwl_mvm_ctx.fi
mut 's/const MAC_UNION_LEN: u64 = 48/const MAC_UNION_LEN: u64 = 44/' "MAC_CONTEXT union size" iwl_mvm_ctx.fi
mut 's/iwl_le.st32(a, h + 20, phy_id_color)/iwl_le.st32(a, h + 16, phy_id_color)/' "BINDING phy offset" iwl_mvm_ctx.fi
mut 's/flags | (nchan << 26)/flags | (nchan << 25)/' "SCAN_CFG channel count field" iwl_mvm_scan.fi
mut 's/const SCAN_DIRECT_LEN: u64 = 34/const SCAN_DIRECT_LEN: u64 = 33/' "SCAN_REQ direct scan entry size" iwl_mvm_scan.fi
mut 's/iwl_le.st8(a, h + 51, tid)/iwl_le.st8(a, h + 50, tid)/' "TX_CMD tid offset" iwl_mvm_tx.fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
