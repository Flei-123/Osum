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
echo "== join: scan, auth, assoc, WPA2 handshake, DHCP over the device seam =="
if $FIRNC tools/wlan/join.fi -o "$D/join" 2> "$D/err"; then ok "tools/wlan/join.fi builds"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
python3 -I tools/wlan/join.py "$D/join" > "$D/out"; grep -v '^  OK' "$D/out"
n=$(grep -c '^  OK' "$D/out"); f=$(grep -c '^  FAIL' "$D/out")
pass=$((pass+n)); fail=$((fail+f))
mut() {
    rm -rf "$D/m"; mkdir -p "$D/m"; cp -r lib/. "$D/m/"
    sed -i "$1" "$D/m/wlan/$3"
    if cmp -s "lib/wlan/$3" "$D/m/wlan/$3"; then bad "mutant did not change source: $2"; return; fi
    if FIRNLIB="$D/m" $FIRNC tools/wlan/join.fi -o "$D/mm" 2> /dev/null && ! python3 -I tools/wlan/join.py "$D/mm" > /dev/null 2>&1; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
}
mut 's/if (\*j).last_status != 0 {\n        connect.auth_angenommen/XX/;0,/if (\*j).last_status != 0 {/s//if (*j).last_status != 99 {/' "auth refusal ignored" join.fi
mut 's/const AKM_PSK: u64 = 2/const AKM_PSK: u64 = 6/' "wrong AKM" join.fi
mut 's/mgmt.auth_build(tx_addr(j), (&mac\[0\]) as u64, bssid)/mgmt.auth_build(tx_addr(j), bssid, (\&mac[0]) as u64)/' "auth addresses swapped" join.fi
mut 's/request_frame(o, sa, bssid, xid, (\*lease).ip, (\*lease).server)/request_frame(o, sa, bssid, xid, 0, (*lease).server)/' "DHCP request without offered address" dhcp_link.fi
mut 's/if dh.xid != xid { return false }/if false { return false }/' "DHCP xid ignored" dhcp_link.fi
mut 's/if (\*lease).kind != llc.D_OFFER { return E_DHCP_NO_OFFER }/if false { return E_DHCP_NO_OFFER }/' "DHCP offer kind unchecked" dhcp_link.fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
