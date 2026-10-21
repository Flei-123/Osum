#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/netui/run.sh -- LW-5 gate (host only, seconds): lib/netui/netui.fi against the independent model in
# tools/netui/model.py (bars, security classes, connection classes, scan list sort/merge/limits, password
# entry), plus the Settings routes for the two network pages, plus control runs with one broken rule each.
# usage: bash tools/netui/run.sh        exit 0 = all OK
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ok=0; bad=0
echo "== netui: logic against the Python model =="
FIRNLIB="$PWD/lib" $FIRNC tools/netui/oracle.fi -o "$D/oracle" 2> "$D/err" || { head -20 "$D/err"; echo "  FAIL  oracle does not build"; exit 1; }
python3 -I tools/netui/model.py "$D/oracle" | tee "$D/out.txt" | grep -v '^  OK'
grep -q '^RESULT pass=[0-9]* fail=0$' "$D/out.txt" && ok=$((ok+1)) || bad=$((bad+1))

echo "== routes: settings://network/wifi and /usb =="
R=kernel/user/settings.d/settings.routes
for r in wifi usb; do
    grep -q "^route settings://network/$r settings.page.network-$r.title " $R && ok=$((ok+1)) || { echo "  FAIL  route network/$r missing"; bad=$((bad+1)); }
    for lc in en de; do
        for k in title kw; do
            grep -q "^settings.page.network-$r.$k = ." locale/$lc/messages && ok=$((ok+1)) || { echo "  FAIL  locale $lc: settings.page.network-$r.$k missing"; bad=$((bad+1)); }
        done
    done
done

echo "== controls: broken library copies must fail =="
mutate() { # name, sed expression
    mkdir -p "$D/m_$1"; cp -r lib "$D/m_$1/lib"
    sed -i "$2" "$D/m_$1/lib/netui/netui.fi"
    if cmp -s lib/netui/netui.fi "$D/m_$1/lib/netui/netui.fi"; then echo "  FAIL  control $1: mutation did not change the source"; bad=$((bad+1)); return; fi
    FIRNLIB="$D/m_$1/lib" $FIRNC tools/netui/oracle.fi -o "$D/o_$1" 2> "$D/e_$1" || { echo "  FAIL  control $1 does not build"; head -5 "$D/e_$1"; bad=$((bad+1)); return; }
    if python3 -I tools/netui/model.py "$D/o_$1" | grep -q '^RESULT pass=[0-9]* fail=0$'; then echo "  FAIL  control $1: broken library still passed"; bad=$((bad+1)); else echo "  OK    control $1: caught"; ok=$((ok+1)); fi
}
mutate bars65 's/if rssi >= 0 - 65 { return 3 }/if rssi >= 0 - 60 { return 3 }/'
mutate unsorted 's/if ra != rb { return ra > rb }/if ra != rb { return false }/'
mutate hiddenfirst 's/if ha != hb { return hb }/if ha != hb { return ha }/'
mutate nodedupe 's/if slen > 0 \&\& l_sec/if slen > 99 \&\& l_sec/'
mutate knownlast 's/return ka > kb/return kb > ka/'
mutate pwmax 's/if p_n >= PW_MAX { return PK_FULL }/if p_n >= 64 { return PK_FULL }/'
mutate pwmin 's/^const PW_MIN: u64 = 8/const PW_MIN: u64 = 6/'
mutate escape 's/        pw_clear()\n        return PK_CANCEL//; s/if ch == 27 {/if ch == 999 {/'
mutate weak 's/return cls == SC_OPEN || cls == SC_WEP || cls == SC_WPA || cls == SC_UNKNOWN/return cls == SC_OPEN || cls == SC_WEP || cls == SC_UNKNOWN/'
mutate keys 's/z == state.Z_M1 || z == state.Z_M2 || z == state.Z_M3/z == state.Z_M1 || z == state.Z_M2/'
echo "NETUI: $ok ok, $bad bad"
[ "$bad" -eq 0 ]
