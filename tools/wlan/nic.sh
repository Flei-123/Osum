#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
stage() {
    rm -rf "$1"; mkdir -p "$1/knet"; cp -r lib/. "$1/"
    sed '/^profile kernel$/d' kernel/net/wlan_net.fi > "$1/knet/wlan_net.fi"
}
echo "== nic: WLAN as a network card (receive key, own-broadcast echo, stack receive ring) =="
stage "$D/lib"
if FIRNLIB="$D/lib" $FIRNC tools/wlan/nic.fi -o "$D/nic" 2> "$D/err"; then ok "tools/wlan/nic.fi builds"; else bad "build"; head -20 "$D/err"; mut 's/\*next = at + ((SUB_HDR + plen + 3) \/ 4) \* 4/*next = ((at + SUB_HDR + plen + 3) \/ 4) * 4/' "A-MSDU padding aligned to the frame instead of the subframe" wlan/ethconv.fi
mut 's/return (octets.ld8(frame, WLAN_HDR) \& QOS_AMSDU) != 0/return false/' "A-MSDU bit ignored" wlan/ethconv.fi
mut 's/if (octets.ld8(frame, 1) \& FC_ORDER) != 0 { hl = hl + 4 }/hl = hl + 0/' "HT control field not skipped" wlan/ethconv.fi
mut 's/    wn_tail = wn_tail - 1$/    wn_tail = wn_tail/' "untake does not put the frame back" knet/wlan_net.fi
mut 's/    wn_txb = wn_txb - n$/    wn_txb = wn_txb/' "untake keeps the octet count" knet/wlan_net.fi
echo "RESULT pass=$pass fail=$fail"; exit 1; fi
python3 -I tools/wlan/nic.py "$D/nic" > "$D/out"; grep -v '^  OK' "$D/out"
pass=$((pass+$(grep -c '^  OK' "$D/out"))); fail=$((fail+$(grep -c '^  FAIL' "$D/out")))
mut() { # sed-expr description file-under-staged-lib
    stage "$D/m"
    sed -i "$1" "$D/m/$3"
    if cmp -s "$D/lib/$3" "$D/m/$3"; then bad "mutant did not change source: $2"; return; fi
    if FIRNLIB="$D/m" $FIRNC tools/wlan/nic.fi -o "$D/mm" 2> /dev/null && ! python3 -I tools/wlan/nic.py "$D/mm" > /dev/null 2>&1; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
}
mut 's/return (&(\*s).gtk\[0\]) as u64/return (\&(*s).ptk[32]) as u64/' "group frames decrypted with the pairwise key" wlan/connect.fi
mut 's/if (\*s).gtk_len < 16 { return 0 }/if (*s).gtk_len > 99 { return 0 }/' "group frame accepted before the group key" wlan/connect.fi
mut 's/^    return true$/    return false/' "echo filter off" wlan/ethconv.fi
mut 's/ld8(frame, 16 + i)/ld8(frame, 10 + i)/' "echo source taken from a2" wlan/ethconv.fi
mut '/(octets.ld8(frame, 1) \& 0x03) != FC_FROMDS/d' "echo filter ignores the DS bits" wlan/ethconv.fi
mut '/(octets.ld8(frame, 4) \& 1) == 0 { return false }/d' "echo filter ignores the group bit" wlan/ethconv.fi
mut 's/static mut wn_rx_depth: u64 = 64/static mut wn_rx_depth: u64 = 8/' "receive ring back to 8 frames" knet/wlan_net.fi
mut 's/static mut wn_rx_depth: u64 = 64/static mut wn_rx_depth: u64 = 1/' "single receive slot" knet/wlan_net.fi
mut 's/if legacy { return rx_free() }/if legacy { return true }/' "legacy mode ignores a busy ring" knet/wlan_net.fi
mut 's/if now_sec == wn_live_sec { return false }/if now_sec == wn_live_sec { return true }/' "full ring read on every pump" knet/wlan_net.fi
mut 's/    wn_live_sec = now_sec/    wn_live_sec = wn_live_sec/' "liveness read not rate limited" knet/wlan_net.fi
mut 's/if rx_queued() != 0 { wn_rx_tail = wn_rx_tail + 1 }/if rx_queued() != 0 { wn_rx_tail = wn_rx_tail }/' "recycle does not advance" knet/wlan_net.fi
mut 's/wn_rx_drop = wn_rx_drop + 1/wn_rx_drop = wn_rx_drop/' "drops not counted" knet/wlan_net.fi
mut 's/wn_rx_tail = wn_rx_head$/wn_rx_tail = wn_rx_tail/' "link down keeps stale frames" knet/wlan_net.fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
