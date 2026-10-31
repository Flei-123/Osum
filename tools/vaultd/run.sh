#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
CC="$ROOT/vendor/firn/bin/firnc"
[ -x "$CC" ] || { echo "compiler missing: $CC" >&2; exit 1; }
D=$(mktemp -d)
SWPID=""
trap '[ -n "$SWPID" ] && kill "$SWPID" 2>/dev/null; rm -rf "$D"; rm -f tests/vaultd/*.test' EXIT
HAVE_SW=0
if command -v swtpm >/dev/null 2>&1; then
    mkdir -p "$D/st"
    swtpm socket --tpmstate "dir=$D/st" --server "type=unixio,path=$D/sock" --ctrl "type=unixio,path=$D/ctl" \
        --tpm2 --flags not-need-init,startup-clear --log "file=$D/sw.log" &
    SWPID=$!
    for _ in $(seq 50); do [ -S "$D/sock" ] && break; sleep 0.1; done
    export TPM_SOCK="$D/sock"
    HAVE_SW=1
fi
pass=0; fail=0
for t in tests/vaultd/*.fi; do
    b=$(basename "$t" .fi)
    case "$b" in *_helper) continue;; esac
    case "$b" in *_sw) [ "$HAVE_SW" = 1 ] || { echo "  SKIP  $b (swtpm missing)"; continue; };; esac
    if ! "$CC" --test "$t" > "$D/$b.out" 2>&1; then
        fail=$((fail + 1)); echo "  FAIL  $b"; grep -E '"status":"fail"|error' "$D/$b.out" | cut -c1-300 | head -5; continue
    fi
    p=$(grep -o '"passed":[0-9]*' "$D/$b.out" | tail -1 | cut -d: -f2)
    f=$(grep -o '"failed":[0-9]*' "$D/$b.out" | tail -1 | cut -d: -f2)
    pass=$((pass + p)); fail=$((fail + f))
    echo "  $b: passed $p failed $f"
done
for f in lib/vaultd/*.fi; do
    if [ "$(grep -acE '^[[:space:]]*//' "$f")" -gt 1 ]; then fail=$((fail + 1)); echo "  FAIL  $f: comments"; fi
done
echo "vaultd: PASS $pass FAIL $fail"
[ "$fail" = 0 ]
