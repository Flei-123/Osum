#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/link.sh -- LW-2 wiring gate (host only): lib/wlan/link.fi (EAPOL dispatch, GTK of message 3 remembered, capability summary) against tools/wlan/link.py, plus control runs with a broken library copy that MUST fail.
# usage: bash tools/wlan/link.sh        exit 0 = all OK
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ok=0; bad=0
echo "== link: EAPOL dispatch + capability summary =="
FIRNLIB="$PWD/lib" $FIRNC tools/wlan/link.fi -o "$D/link" 2> "$D/err" || { head -20 "$D/err"; echo "  FAIL  oracle does not build"; exit 1; }
python3 -I tools/wlan/link.py "$D/link" | tee "$D/out.txt" | grep -v '^  OK'
grep -q '^RESULT pass=[0-9]* fail=0$' "$D/out.txt" && ok=$((ok+1)) || bad=$((bad+1))
mutate() { # name, sed expression, [file in lib/wlan, default link.fi]
    local f=${3:-link.fi}
    mkdir -p "$D/m_$1"; cp -r lib "$D/m_$1/lib"
    sed -i "$2" "$D/m_$1/lib/wlan/$f"
    if cmp -s "lib/wlan/$f" "$D/m_$1/lib/wlan/$f"; then echo "  FAIL  control $1: mutation did not change the source"; bad=$((bad+1)); return; fi
    FIRNLIB="$D/m_$1/lib" $FIRNC tools/wlan/link.fi -o "$D/link_$1" 2> "$D/err_$1" || { echo "  FAIL  control $1 does not build"; bad=$((bad+1)); return; }
    if python3 -I tools/wlan/link.py "$D/link_$1" | grep -q '^RESULT pass=[0-9]* fail=0$'; then echo "  FAIL  control $1: broken library still passed"; bad=$((bad+1)); else echo "  OK    control $1: broken library is caught"; ok=$((ok+1)); fi
}
mutate nogtk 's/^            after_m3(l, eapol, elen)$//'
mutate nowidth 's/caps.best_rate_kbps(&c, w)/0 as u64/'
# control: the old behaviour (a bad-MIC message 3 aborts the run with event 'x') must be caught
mutate m3abort 's/^        (\*s).fehler = F_MIC$/&\n        state.ereignis(\&(*s).lauf, 120)/' connect.fi
echo "RESULT ok=$ok bad=$bad"
[ "$bad" -eq 0 ]
