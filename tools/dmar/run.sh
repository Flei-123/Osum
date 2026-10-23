#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dmar/run.sh -- host gate: DMAR parser (lib/hwinv/dmarparse) + report keys (dmarsum) + mutations.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
python3 tools/dmar/gen.py tools/dmar/check.tpl "$T/check.fi" >/dev/null && ok "tables generated" || { bad "generator"; exit 1; }
$FIRNC "$T/check.fi" -o "$T/c" 2> "$T/c.err" && ok "check builds" || { bad "build"; head -8 "$T/c.err"; echo "DMAR: $pass passed, $fail failed"; exit 1; }
"$T/c" > "$T/c.txt" 2>&1
n1=$(grep -c '^OK' "$T/c.txt"); n2=$(grep -c '^FAIL' "$T/c.txt")
sed -n 's/^FAIL /  FAIL  check: /p' "$T/c.txt"
[ "$n2" = 0 ] && [ "$n1" -ge 45 ] && ok "parser+report: $n1 checks OK, 0 FAIL" || bad "parser+report ($n1 ok, $n2 fail)"
pass=$((pass+n1))
mut() {
    rm -rf "$T/lib-mut"; mkdir -p "$T/lib-mut"
    for d in lib/*; do [ "$(basename "$d")" = hwinv ] || ln -sfn "$ROOT/$d" "$T/lib-mut/$(basename "$d")"; done
    mkdir -p "$T/lib-mut/hwinv"
    for f in lib/hwinv/*.fi; do cp "$f" "$T/lib-mut/hwinv/"; done
    sed -i "$3" "$T/lib-mut/hwinv/$2"
    cmp -s "lib/hwinv/$2" "$T/lib-mut/hwinv/$2" && { bad "mutation $1 did not change the lib"; return; }
    if FIRNLIB="$T/lib-mut" $FIRNC "$T/check.fi" -o "$T/m" 2>/dev/null; then
        local m; m=$("$T/m" 2>&1 | grep -c '^FAIL')
        [ "$m" -gt 0 ] && ok "mutation ($1) -> $m red checks" || bad "mutation $1 stayed green"
    else bad "mutation $1 build failed"; fi
}
mut "rmrr type shifted" dmarparse.fi 's/const T_RMRR: u64 = 1/const T_RMRR: u64 = 9/'
mut "drhd base offset wrong" dmarparse.fi 's/return ld64(s + 8)/return ld64(s + 16)/'
mut "optin flag bit wrong" dmarparse.fi 's/(flags(t) >> 2) \& 1/(flags(t) >> 3) \& 1/'
mut "haw off by one" dmarparse.fi 's/ld8(t + H_HAW) + 1/ld8(t + H_HAW)/'
mut "checksum inverted" dmarparse.fi 's/return (s \& 255) == 0/return (s \& 255) != 0/'
mut "bad struct length accepted" dmarparse.fi 's/return l >= 4 \&\& at + l <= end/return at + l <= end/'
mut "translation on never seen" dmarsum.fi 's/v\[TRANS as usize\] = 2/v[TRANS as usize] = 1/'
mut "present never recognised" dmarsum.fi 's/v\[PRESENT as usize\] = 1/v[PRESENT as usize] = 0/'
mut "units count key wrong" dmarsum.fi 's/"drhd=\\0"/"drhx=\\0"/'
echo "DMAR: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
