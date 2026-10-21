#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/lw2.sh -- LW-2 gate (host only): group key rekey (lib/wlan/groupkey.fi) + HT/VHT/HE capability
# parsing (lib/wlan/caps.fi) against an independent Python model (tools/wlan/lw2.py), plus two control runs
# with a deliberately broken library copy (replay check removed, "already installed" check removed) that MUST fail.
# usage: bash tools/wlan/lw2.sh        exit 0 = all OK
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
ok=0; bad=0
echo "== lw2: group rekey + capabilities =="
FIRNLIB="$PWD/lib" $FIRNC tools/wlan/lw2.fi -o "$D/lw2" 2> "$D/err" || { head -20 "$D/err"; echo "  FAIL  oracle does not build"; exit 1; }
python3 -I tools/wlan/lw2.py "$D/lw2" | tee "$D/out.txt" | grep -v '^  OK'
grep -q '^RESULT pass=[0-9]* fail=0$' "$D/out.txt" && ok=$((ok+1)) || bad=$((bad+1))
mutate() { # name, sed expression
    mkdir -p "$D/m_$1"; cp -r lib "$D/m_$1/lib"
    sed -i "$2" "$D/m_$1/lib/wlan/groupkey.fi"
    if cmp -s lib/wlan/groupkey.fi "$D/m_$1/lib/wlan/groupkey.fi"; then echo "  FAIL  control $1: mutation did not change the source"; bad=$((bad+1)); return; fi
    FIRNLIB="$D/m_$1/lib" $FIRNC tools/wlan/lw2.fi -o "$D/lw2_$1" 2> "$D/err_$1" || { echo "  FAIL  control $1 does not build"; bad=$((bad+1)); return; }
    if python3 -I tools/wlan/lw2.py "$D/lw2_$1" | grep -q '^RESULT pass=[0-9]* fail=0$'; then echo "  FAIL  control $1: broken library still passed"; bad=$((bad+1)); else echo "  OK    control $1: broken library is caught"; ok=$((ok+1)); fi
}
mutate noreplay 's/counter <= (\*gs).last_counter/false/'
mutate reinstall 's/var same: bool = (\*gs).have_gtk \&\& (\*gs).key_idx == idx/var same: bool = false/; s/^        same = diff == 0$/        same = false/'
echo "RESULT ok=$ok bad=$bad"
[ "$bad" -eq 0 ]
