#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
CC="$ROOT/vendor/firn/bin/firnc"
[ -x "$CC" ] || { echo "compiler missing: $CC" >&2; exit 1; }
D=$(mktemp -d)
trap 'rm -rf "$D"; rm -f tests/vaultlib/*.test' EXIT
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
TOOL="$D/vtool"
if "$CC" tools/vaultlib/vtool.fi -o "$TOOL" > "$D/vtool.out" 2>&1; then
    V="$D/venv"
    if python3 -m venv "$V" > /dev/null 2>&1 && "$V/bin/pip" install -q argon2-cffi cryptography > "$D/pip.out" 2>&1; then
        PY="$V/bin/python"
    else
        PY=python3
    fi
    mkdir "$D/work"
    "$PY" tools/vaultlib/against.py "$TOOL" "$D/work" > "$D/against.out" 2>&1
    tail -n 4 "$D/against.out"
    af=$(grep -o 'FAIL [0-9]*' "$D/against.out" | tail -1 | cut -d' ' -f2)
    ap=$(grep -o 'OK [0-9]*' "$D/against.out" | tail -1 | cut -d' ' -f2)
    if [ -z "$af" ]; then fail=$((fail + 1)); echo "  FAIL  against.py crashed"; head -n 8 "$D/against.out"; else pass=$((pass + ap)); fail=$((fail + af)); fi
else
    fail=$((fail + 1)); echo "  FAIL  vtool build"; head -n 5 "$D/vtool.out"
fi
for f in lib/std/cbor.fi lib/std/cborread.fi lib/std/cborcanon.fi lib/std/utf8.fi lib/vault/*.fi tools/vaultlib/vtool.fi; do
    [ -f "$f" ] || continue
    if grep -aqE '^[[:space:]]*//' "$f" && [ "$(grep -acE '^[[:space:]]*//' "$f")" -gt 1 ]; then fail=$((fail + 1)); echo "  FAIL  $f: comments"; fi
done
echo "vaultlib: PASS $pass FAIL $fail"
[ "$fail" = 0 ]
