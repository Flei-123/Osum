#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/mvm.sh -- gate for lib/wlan/iwl_mvm.fi (HP-9c.3 MVM command encoders): every command byte-equal to an
# independent struct.pack reference (tools/wlan/mvm_ref.py), plus 3 mutants that MUST differ.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
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
mut 's/st8(a, HDR + 17, channel)/st8(a, HDR + 16, channel)/' "PHY_CONTEXT channel octet offset"
mut 's/return HDR + 36/return HDR + 40/' "PHY_CONTEXT length"
mut 's/const PHY_CFG_V3_LEN: u64 = 28/const PHY_CFG_V3_LEN: u64 = 24/' "PHY_CONFIGURATION_CMD v3 length"
mut 's/const SF_INIT_OFF: u64 = 3/const SF_INIT_OFF: u64 = 2/' "SF_CFG state"
mut 's/st32(a, HDR + 52 + k \* 4, SF_AGING_DEF)/st32(a, HDR + 56 + k * 4, SF_AGING_DEF)/' "SF_CFG full-on timeout offset"
mut 's/const BLOCK_SHIFT: u64 = 15/const BLOCK_SHIFT: u64 = 14/' "FW_PAGING_BLOCK_CMD block size" iwl_paging.fi
mut 's/const FLAG_SECURED: u64 = 0x200/const FLAG_SECURED: u64 = 0x400/' "FW_PAGING_BLOCK_CMD flags" iwl_paging.fi
mut 's/const BT_MODS_DEFAULT: u64 = 0x14/const BT_MODS_DEFAULT: u64 = 0x04/' "BT_CONFIG enabled modules"
mut 's/var fl: u64 = 2 |/var fl: u64 = 3 |/' "CCMP cipher flag"
mut 's/octets.st32(a, h + 8, mac_type)/octets.st32(a, h + 12, mac_type)/' "MAC_CONTEXT mac_type offset" iwl_mvm_ctx.fi
mut 's/const MAC_UNION_LEN: u64 = 48/const MAC_UNION_LEN: u64 = 44/' "MAC_CONTEXT union size" iwl_mvm_ctx.fi
mut 's/octets.st32(a, h + 20, phy_id_color)/octets.st32(a, h + 16, phy_id_color)/' "BINDING phy offset" iwl_mvm_ctx.fi
mut 's/flags | (nchan << 26)/flags | (nchan << 25)/' "SCAN_CFG channel count field" iwl_mvm_scan.fi
mut 's/const SCAN_DIRECT_LEN: u64 = 34/const SCAN_DIRECT_LEN: u64 = 33/' "SCAN_REQ direct scan entry size" iwl_mvm_scan.fi
mut 's/octets.st8(a, h + 19, n_aps)/octets.st8(a, h + 18, n_aps)/' "SCAN_REQ v7 n_aps offset" iwl_mvm_scan.fi
mut 's/octets.st16(a, h + 22, budget)/octets.st16(a, h + 20, budget)/' "SCAN_REQ v7 budget offset" iwl_mvm_scan.fi
mut 's/const SCAN_V7_HEAD_LEN: u64 = iwl_buf.HDR + 48/const SCAN_V7_HEAD_LEN: u64 = iwl_buf.HDR + 44/' "SCAN_REQ v7 head length" iwl_mvm_scan.fi
mut 's/octets.st8(a, h + 51, tid)/octets.st8(a, h + 50, tid)/' "TX_CMD tid offset" iwl_mvm_tx.fi
mut 's/const OFF_STA_TYPE: u64 = 35/const OFF_STA_TYPE: u64 = 33/' "ADD_STA v10 station_type offset" iwl_mvm_sta.fi
mut 's/const STA_LEN_V8: u64 = 48/const STA_LEN_V8: u64 = 52/' "ADD_STA v10 length" iwl_mvm_sta.fi
mut 's/const DATA_PATH_GROUP: u64 = 5/const DATA_PATH_GROUP: u64 = 1/' "DQA_ENABLE group" iwl_mvm_txq.fi
mut 's/octets.st16(a, h + 52, pm_timeout)/octets.st16(a, h + 54, pm_timeout)/' "TX_CMD pm_frame_timeout offset" iwl_mvm_tx.fi
mut 's/const OFFLOAD_PAD: u64 = 0x2000/const OFFLOAD_PAD: u64 = 0x4000/' "TX_CMD offload_assist PAD bit" iwl_mvm_tx.fi
mut 's/const PM_FRAME_ASSOC: u64 = 3/const PM_FRAME_ASSOC: u64 = 2/' "pm_frame_timeout for association requests" iwl_mvm_tx.fi
mut 's/if st == SUBTYPE_ACTION { return 0 }/if st == SUBTYPE_ACTION { return 2 }/' "pm_frame_timeout for action frames" iwl_mvm_tx.fi
mut 's/const TID_MGMT: u64 = 8/const TID_MGMT: u64 = 0/' "TX_CMD tid for management and non-QoS frames" iwl_mvm_tx.fi
mut 's/var bytes: u64 = flen + 8/var bytes: u64 = flen + 4/' "byte-count table entry in bytes" iwl_mvm_txq.fi
mut 's/const CMD_LQ: u64 = 0x4E/const CMD_LQ: u64 = 0x4F/' "LQ_CMD command id" iwl_mvm_rs.fi
mut 's/octets.st32(a, h + 20 + i \* 4, rate)/octets.st32(a, h + 24 + i * 4, rate)/' "LQ_CMD rs_table offset" iwl_mvm_rs.fi
mut 's/octets.st8(a, h + 15, LQ_AGG_FRAME_LIMIT)/octets.st8(a, h + 14, LQ_AGG_FRAME_LIMIT)/' "LQ_CMD agg_frame_cnt_limit offset" iwl_mvm_rs.fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
