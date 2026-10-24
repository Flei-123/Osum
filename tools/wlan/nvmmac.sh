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
echo "== nvmmac: MAC override section =="
cat > "$D/exp" <<'X'
1061122334455
0000000000000
0000000000000
0000000000000
0000000000000
102ccaaffee01
X
if $FIRNC tools/wlan/nvmmac.fi -o "$D/t" 2> "$D/err"; then ok "tools/wlan/nvmmac.fi builds"; else bad "build"; head -20 "$D/err"; echo "RESULT pass=$pass fail=$fail"; exit 1; fi
"$D/t" > "$D/out"
n=0
while read -r want; do
    n=$((n+1)); got=$(sed -n "${n}p" "$D/out")
    [ "$got" = "$want" ] && ok "case $n: $want" || bad "case $n: got '$got' want '$want'"
done < "$D/exp"
mut() {
    mkdir -p "$D/m" && cp -r lib/. "$D/m/"; sed -i "$1" "$D/m/wlan/iwl_nvmmac.fi"
    if FIRNLIB="$D/m" $FIRNC tools/wlan/nvmmac.fi -o "$D/mm" 2> /dev/null && "$D/mm" > "$D/mo" 2>/dev/null && ! cmp -s "$D/mo" "$D/out"; then ok "mutant caught: $2"; else bad "mutant NOT caught: $2"; fi
}
mut 's/const MAO_MAC_OFF: u64 = 2/const MAO_MAC_OFF: u64 = 1/' "MAC offset"
mut 's/iwl_le.ld8(m, 0) \& 1) != 0/iwl_le.ld8(m, 0) \& 2) != 0/' "multicast bit"
mut 's/ld8(m, 5) == 0x00/ld8(m, 5) == 0x01/' "reserved address"
mut 's/if any == 0 { return false }//' "all-zero address"
mut 's/const MAO_MIN_LEN: u64 = 8/const MAO_MIN_LEN: u64 = 6/' "minimum length"
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
