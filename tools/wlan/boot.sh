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
echo "== boot: INIT/NVM/calibration stages + diagnostics =="
python3 -I tools/wlan/boot_ref.py > "$D/exp"
if $FIRNC tools/wlan/boot.fi -o "$D/boot" 2> "$D/err"; then ok "tools/wlan/boot.fi builds"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
"$D/boot" > "$D/out"
grep -a '^S \|^cmd ' "$D/out" > "$D/got"
if diff "$D/exp" "$D/got" > "$D/diff"; then ok "$(wc -l < "$D/exp") scenario/command lines == Python reference"; else bad "output differs"; head -10 "$D/diff"; fi
has() { grep -qaF -- "$1" "$D/out" && ok "$2" || bad "$2 -- '$1' missing"; }
has 'D phase=ready' "diag: phase=ready after full run"
has 'D alive=yes init_alive=yes rt_alive=yes' "diag: both ALIVEs"
has 'D nvm=ok bytes=5194 secs=5' "diag: NVM bytes and sections"
has 'D calib=5 bytes=2088 replayed=5' "diag: calibration collected and replayed"
has 'D calibpkt: seen=7 bytes=2132 max=2060 drops=0 skipped=1 skip_type=3 len=6' "diag: calibpkt counters (7 packets incl. the HP type-5 TXP group, 1 unused type skipped)"
has 'D calibpkt_bad: rc=-71 plen=2060 type=5 len=2056 hex=0500080807000000000000002a140000284800002678000006b4000004e00000' "diag: old numbering reproduces the HP dump byte for byte (rc=-71, type 5, len 2056)"
has 'D failed_at=nvm' "diag: failed_at names the phase"
has 'D err_text=command queue not implemented' "diag: err_text for -60"
mut() {
    local mod=$3
    mkdir -p "$D/m" && cp -r lib/. "$D/m/"; sed -i "$1" "$D/m/wlan/$mod"
    if FIRNLIB="$D/m" $FIRNC tools/wlan/boot.fi -o "$D/mm" 2> /dev/null; then
        "$D/mm" 2>/dev/null | grep -a '^S \|^cmd ' > "$D/mo"
        if ! cmp -s "$D/mo" "$D/got"; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
    else bad "mutant did not build: $2"; fi
}
mut 's/const PD_CALIB_TXP: u64 = 5/const PD_CALIB_TXP: u64 = 9/' "type 5 no longer a stored section" iwl_phydb.fi
mut 's/if (\*db).legacy != 0 { return E_PD_TYPE }/if true { return E_PD_TYPE }/' "unknown types rejected again" iwl_phydb.fi
mut 's/if ta != tb { return ta < tb }/if ta != tb { return ta > tb }/' "replay order reversed" iwl_phydb.fi
mut 's/const NVM_CHUNK: u64 = 2048/const NVM_CHUNK: u64 = 1024/' "NVM chunk size" iwl_boot.fi
mut 's/== typ && (\*db).id\[i as usize\] == id/== typ \&\& false/' "duplicate calibration entry not replaced" iwl_phydb.fi
mut 's/qid: 0, seq: 0, tx_ant: 3/qid: 0, seq: 0, tx_ant: 1/' "TX antenna mask" iwl_boot.fi
mut 's/if id == iwl_phydb.CMD_CALIB_RES {/if id == 0x6D {/' "calibration notifications ignored" iwl_boot.fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" = 0 ]
