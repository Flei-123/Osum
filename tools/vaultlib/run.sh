#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
CC="$ROOT/vendor/firn/bin/firnc"
[ -x "$CC" ] || { echo "compiler missing: $CC" >&2; exit 1; }
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
for t in tests/vaultlib/*.fi; do
    b=$(basename "$t" .fi)
    case "$b" in *_helper) continue;; esac
    if ! "$CC" --test "$t" > "$D/$b.out" 2>&1; then
        fail=$((fail + 1)); echo "  FAIL  $b"; grep -E '"status":"fail"|error' "$D/$b.out" | cut -c1-300 | head -5; continue
    fi
    p=$(grep -o '"passed":[0-9]*' "$D/$b.out" | tail -1 | cut -d: -f2)
    f=$(grep -o '"failed":[0-9]*' "$D/$b.out" | tail -1 | cut -d: -f2)
    pass=$((pass + p)); fail=$((fail + f))
    echo "  $b: passed $p failed $f"
done
for f in lib/std/cbor.fi lib/std/cborread.fi lib/std/cborcanon.fi lib/std/utf8.fi lib/vault/*.fi; do
    [ -f "$f" ] || continue
    if grep -aqE '^[[:space:]]*//' "$f" && [ "$(grep -acE '^[[:space:]]*//' "$f")" -gt 1 ]; then fail=$((fail + 1)); echo "  FAIL  $f: comments"; fi
done
echo "vaultlib: PASS $pass FAIL $fail"
[ "$fail" = 0 ]
