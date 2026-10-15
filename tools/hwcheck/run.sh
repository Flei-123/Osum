#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hwcheck/run.sh -- E2: the hardware check engine (lib/hwcheck/check.fi), host only, + 2 mutations.
#   bash tools/hwcheck/run.sh
# The guest side (`sysinfo --hwcheck`, `--export`) is measured by tools/sysinfo/run.sh.
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
$FIRNC tools/hwcheck/check.fi -o "$T/c" 2> "$T/c.err" && ok "check test builds" || { bad "build"; head -5 "$T/c.err"; echo "HWCHECK: $pass passed, $fail failed"; exit 1; }
"$T/c" > "$T/c.txt" 2>&1
n1=$(grep -c '^OK' "$T/c.txt"); n2=$(grep -c '^FAIL' "$T/c.txt")
sed -n 's/^FAIL /  FAIL  check: /p' "$T/c.txt"
[ "$n2" = 0 ] && [ "$n1" -ge 25 ] && ok "engine: $n1 checks OK, 0 FAIL" || bad "engine ($n1 ok, $n2 fail)"
pass=$((pass+n1))
mkdir -p "$T/lib-mut"
for d in lib/*; do [ "$(basename "$d")" = hwcheck ] || ln -sfn "$ROOT/$d" "$T/lib-mut/$(basename "$d")"; done
mkdir -p "$T/lib-mut/hwcheck"
mut() { # <name> <sed-expr>
    sed "$2" lib/hwcheck/check.fi > "$T/lib-mut/hwcheck/check.fi"
    cmp -s lib/hwcheck/check.fi "$T/lib-mut/hwcheck/check.fi" && { bad "mutation $1 did not change the lib"; return; }
    if FIRNLIB="$T/lib-mut" $FIRNC tools/hwcheck/check.fi -o "$T/m" 2>/dev/null; then
        local m; m=$("$T/m" 2>&1 | grep -c '^FAIL')
        [ "$m" -gt 0 ] && ok "mutation ($1) -> $m red checks" || bad "mutation $1 stayed green"
    else bad "mutation $1 build failed"; fi
}
mut "wlan class 0280 widened to any 02xx" 's/same4(l, 48, 50, 56, 48)/(ld(l, 8) == 48 \&\& ld(l, 9) == 50)/'
mut "audio accepts 0402" 's/same4(l, 48, 52, 48, 49)/same4(l, 48, 52, 48, 50)/'
echo "HWCHECK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
