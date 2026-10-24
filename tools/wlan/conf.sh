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
echo "== wlanconf: /etc/wlan.conf parse, PMK, autostart state machine over the join harness =="
if $FIRNC tools/wlan/join.fi -o "$D/join" 2> "$D/err"; then ok "tools/wlan/join.fi builds with wlanconf + autojoin"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
python3 -I tools/wlan/conf.py "$D/join" > "$D/out"; grep -v '^  OK' "$D/out"
n=$(grep -c '^  OK' "$D/out"); f=$(grep -c '^  FAIL' "$D/out")
pass=$((pass+n)); fail=$((fail+f))
mut() {
    rm -rf "$D/m"; mkdir -p "$D/m"; cp -r lib/. "$D/m/"
    sed -i "$1" "$D/m/wlan/$3"
    if cmp -s "lib/wlan/$3" "$D/m/wlan/$3"; then bad "mutant did not change source: $2"; return; fi
    if FIRNLIB="$D/m" $FIRNC tools/wlan/join.fi -o "$D/mm" 2> /dev/null && ! python3 -I tools/wlan/conf.py "$D/mm" > /dev/null 2>&1; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
}
mut 's/(\*c).psk_len < PSK_MIN/false/' "short password accepted" wlanconf.fi
mut 's/const PSK_MAX: usize = 63/const PSK_MAX: usize = 64/' "64-character password accepted" wlanconf.fi
mut 's/const SSID_MAX: usize = 32/const SSID_MAX: usize = 33/' "33-character name accepted" wlanconf.fi
mut 's/== 13 as u8) { n = n - 1 }/== 99 as u8) { n = n - 1 }/' "CR not stripped" wlanconf.fi
mut '/^fn conf_clear/,/^}/s/(\*c).psk\[i\] = 0 as u8/(*c).psk[i] = (*c).psk[i]/' "password not wiped" wlanconf.fi
mut 's/if !(\*c).have_psk { return E_CONF_NO_PSK }/if false { return E_CONF_NO_PSK }/' "missing password line accepted" wlanconf.fi
mut 's/if s > BACKOFF_MAX { s = BACKOFF_MAX }/if false { s = s }/' "backoff without cap" autojoin.fi
mut 's/if s == 0 { s = BACKOFF_MIN } else { s = s \* 2 }/s = BACKOFF_MIN/' "backoff does not grow" autojoin.fi
mut 's/(\*a).state = AS_UP/(*a).state = AS_RETRY/' "success not reported" autojoin.fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
