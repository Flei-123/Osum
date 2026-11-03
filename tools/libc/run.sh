#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
D=$(mktemp -d)
osum_tmp_guard "${1:-}" "$D"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
pass=0
fail=0
ok() { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

build_run() {
    local lib=$1 out=$2
    FIRNLIB=$lib "$FIRNC" tools/libc/suite.fi -o "$out" > "$out.log" 2>&1 || return 2
    "$out" > /dev/null 2>&1
}

echo "== 1. host suite over the pure libc modules =="
build_run "$PWD/lib" "$D/suite"; rc=$?
[ $rc -eq 0 ] && ok "octets, numeric, hexdigit, pathname, textsearch, locks agree with the reference values" || bad "suite rc=$rc"

echo "== 2. counter-proofs: a broken module must fail the suite =="
n=0
for edit in \
    "numeric.fi|s/return imin(imax(v, lo), hi)/return imax(imin(v, hi), lo) + 1/" \
    "octets.fi|s/return ld8(p, i) | (ld8(p, i + 1) << 8)/return ld8(p, i)/" \
    "hexdigit.fi|s/return v + 87/return v + 88/" \
    "pathname.fi|s/return at - 1/return at/" \
    "textsearch.fi|s/return text.equal(p + lp - ls, suffix)/return true/"; do
    mod=${edit%%|*}
    expr=${edit#*|}
    n=$((n+1))
    cp -r lib "$D/lib$n"
    sed -i "$expr" "$D/lib$n/libc/$mod"
    if cmp -s "lib/libc/$mod" "$D/lib$n/libc/$mod"; then bad "patch for $mod did not apply"; continue; fi
    build_run "$D/lib$n" "$D/bad$n"; rc=$?
    [ $rc -eq 1 ] && ok "broken $mod is caught" || bad "broken $mod not caught (rc=$rc)"
done

echo "== $pass ok, $fail fail =="
[ $fail -eq 0 ]
