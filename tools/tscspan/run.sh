#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0
fail=0
ok() { pass=$((pass + 1)); echo "OK   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }

baseline="$(cat tools/tscspan/baseline.txt)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if python3 -I tools/tscspan/lint.py . "$baseline" > "$work/real.log"; then
    ok "raw tsc spans within baseline $baseline ($(tail -1 "$work/real.log"))"
else
    bad "raw tsc spans exceed baseline $baseline"
    tail -5 "$work/real.log"
fi

count="$(tail -1 "$work/real.log" | cut -d' ' -f1)"
if [ "$count" -lt "$baseline" ]; then
    bad "baseline $baseline is stale, lower it to $count"
else
    ok "baseline is tight"
fi

mkdir -p "$work/mut/kernel/probe"
git -C "$work/mut" init -q
printf 'fn spin() {\n    let t0: u64 = time.tsc()\n    let d: u64 = time.tsc() - t0\n}\n' > "$work/mut/kernel/probe/a.fi"
git -C "$work/mut" add -A
if python3 -I tools/tscspan/lint.py "$work/mut" 0 > /dev/null; then
    bad "counter-proof: raw tsc subtraction was not caught"
else
    ok "counter-proof: raw tsc subtraction is caught"
fi

printf 'fn spin() {\n    let t0: u64 = time.tsc()\n    let d: u64 = time.since(t0)\n}\n' > "$work/mut/kernel/probe/a.fi"
if python3 -I tools/tscspan/lint.py "$work/mut" 0 > /dev/null; then
    ok "control: time.since span passes"
else
    bad "control: time.since span was flagged"
fi

echo "tscspan: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
