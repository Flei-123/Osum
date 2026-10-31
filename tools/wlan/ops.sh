#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/ops.sh -- gate for lib/wlan/iwl_ops.fi + lib/wlan/mgmt.fi (HP-9c.4): device operations of the 8265
# (contexts, scan, peer, keys, TX/RX framing) over a loopback transport, auth/assoc/EAPOL frames against Python references.
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
echo "== ops: 8265 device operations =="
if $FIRNC tools/wlan/ops.fi -o "$D/ops" 2> "$D/err"; then ok "tools/wlan/ops.fi builds"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
python3 -I tools/wlan/ops.py "$D/ops" > "$D/out"; grep -v '^  OK' "$D/out"
n=$(grep -c '^  OK' "$D/out"); f=$(grep -c '^  FAIL' "$D/out")
pass=$((pass+n)); fail=$((fail+f))
mut() { # sed-expr description module
    rm -rf "$D/m"; mkdir -p "$D/m"; cp -r lib/. "$D/m/"
    sed -i "$1" "$D/m/wlan/$3"
    if cmp -s "lib/wlan/$3" "$D/m/wlan/$3"; then bad "mutant did not change source: $2"; return; fi
    if FIRNLIB="$D/m" $FIRNC tools/wlan/ops.fi -o "$D/mm" 2> /dev/null && ! python3 -I tools/wlan/ops.py "$D/mm" > /dev/null 2>&1; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
}
mut 's/offset = 1 + (id \& 3)/offset = 0/' "group key offset" iwl_ops.fi
mut 's/flags = flags | iwl_mvm_tx.TX_FLG_SEQ_CTL/flags = flags/' "management frames without SEQ_CTL" iwl_ops.fi
mut 's/const KEY_INFO_M2: u64 = 0x010A/const KEY_INFO_M2: u64 = 0x010B/' "message 2 key info" mgmt.fi
mut 's/iwl_le.st8(out, 81 + i, mic\[i as usize\] as u64)/iwl_le.st8(out, 82 + i, mic[i as usize] as u64)/' "MIC position" mgmt.fi
mut 's/iwl_le.st16(out, 26, 1)/iwl_le.st16(out, 26, 2)/' "auth sequence number" mgmt.fi
mut 's/RATE_6M_OFDM, STA_AP, sec,/RATE_6M_OFDM, STA_AUX, sec,/' "TX station id" iwl_ops.fi
mut 's/(\*o).rssi = 0 - (best as i64)/(*o).rssi = (best as i64)/' "RSSI sign" iwl_ops.fi
mut 's/ \&\& fw_uid + 1 != (\*o).scan_uid//' "scan complete uid off by one from the firmware" iwl_ops.fi
mut 's/if fw_uid != (\*o).scan_uid \&\& fw_uid + 1 != (\*o).scan_uid { return }//' "scan complete uid not checked" iwl_ops.fi
mut 's/    (\*o).fail_step = step/    (*o).fail_step = 0/' "failed setup step not recorded" iwl_ops.fi
mut 's/    if !step_done(o, STEP_PHY_CTX) {/    if true {/' "setup retry resends finished steps" iwl_ops.fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
