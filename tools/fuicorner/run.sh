#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if vendor/firn/bin/firnc -o "$D/unit" tools/fuicorner/unit.fi > "$D/cc.log" 2>&1; then
    ok "fui.core + ecke build on the host"
else
    bad "build failed"; head -20 "$D/cc.log" | sed 's/^/        /'
    echo "FUICORNER: $pass passed, $fail failed"; exit 1
fi
"$D/unit" "$D/table.txt" || { bad "unit exited $?"; echo "FUICORNER: $pass passed, $fail failed"; exit 1; }
res=$(python3 -I tools/fuicorner/check.py "$D/table.txt")
echo "  INFO  $res"
get() { echo "$res" | grep -o "$1=[0-9]*" | cut -d= -f2; }
[ "$(get vs_ecke)" = 0 ] && ok "widget corner coverage == lib/ecke.fi for r=1..24 (window and widget corners share one curve)" || bad "widget corners differ from lib/ecke.fi in $(get vs_ecke) pixels"
[ "$(get vs_ref8)" = 0 ] && ok "matches the independent 8x8 reference model" || bad "differs from the 8x8 reference in $(get vs_ref8) pixels"
[ "$(get vs_ref4)" -gt 100 ] && ok "counter-proof: the old 4x4 model differs in $(get vs_ref4) pixels (the check measures the change)" || bad "counter-proof: old 4x4 model differs in only $(get vs_ref4) pixels"
echo "FUICORNER: $pass passed, $fail failed"
[ "$fail" = 0 ]
