#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/firnenv.sh
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

$FIRNC tools/ime/ime_check.fi -o "$D/ic" 2> "$D/ic.err" || { bad "ime_check build"; head -5 "$D/ic.err"; echo "IME: $pass passed, $fail failed"; exit 1; }
"$D/ic" > "$D/ic.out"
while IFS= read -r line; do
    case "$line" in
        OK*) ok "${line#OK   }" ;;
        *) bad "${line#FAIL }" ;;
    esac
done < "$D/ic.out"
[ "$(grep -c '^OK' "$D/ic.out")" -ge 7 ] && ok "all 7 promises reported" || bad "fewer than 7 promises reported"

mkdir -p "$D/mut"
cp -r "$FIRN_TOOLCHAIN/lib/." "$D/mut/"
cp -r "$ROOT/lib/." "$D/mut/"
sed -i 's/return S_BASE + /return 1 + S_BASE + /' "$D/mut/fui/ime.fi"
if cmp -s "$D/mut/fui/ime.fi" "$FIRN_TOOLCHAIN/lib/fui/ime.fi"; then
    bad "mutant did not change ime.fi"
else
    FIRNLIB="$D/mut" $FIRNC tools/ime/ime_check.fi -o "$D/mc" 2> "$D/mc.err" && "$D/mc" > "$D/mc.out"
    grep -q '^FAIL hangul' "$D/mc.out" 2>/dev/null && ok "counter-proof: broken Hangul composition turns the check red" || bad "mutant not detected"
fi
echo "IME: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
