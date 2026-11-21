#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0

run_host() {
    local libdir="$1" out="$2"
    FIRNLIB="$libdir" "$FIRNC" --profile=app tools/autostart/host.fi -o "$out/host" > "$out/build" 2>&1 || return 2
    "$out/host" > "$out/out"
}

run_host "$PWD/lib" "$T" || { echo "FAIL  host build/run"; grep -v '^warning' "$T/build" | head -20; grep '^FAIL' "$T/out" | head; exit 1; }
grep '^FAIL' "$T/out" | head -20
checks=$(sed -n "s/^checks=\([0-9]*\) fails=.*/\1/p" "$T/out")
fails=$(sed -n "s/^checks=.* fails=\([0-9]*\)/\1/p" "$T/out")
pass=$((pass + ${checks:-0} - ${fails:-1}))
fail=$((fail + ${fails:-1}))

mutate() {
    local label="$1" expr="$2"
    local M="$T/mut-$label"
    mkdir -p "$M/lib/autostart"
    cp -r lib/. "$M/lib/"
    python3 -I - "$M/lib/autostart/model.fi" "$expr" <<'PY'
import sys
path, spec = sys.argv[1], sys.argv[2]
old, new = spec.split("=>", 1)
s = open(path).read()
assert old in s, old
open(path, "w").write(s.replace(old, new, 1))
PY
    mkdir -p "$M/out"
    if run_host "$M/lib" "$M/out" && ! grep -q '^FAIL' "$M/out/out"; then
        echo "FAIL  mutant $label survived"
        fail=$((fail + 1))
    else
        echo "OK    mutant $label caught"
        pass=$((pass + 1))
    fi
}

mutate services-unlocked "return kind(i) == KIND_SERVICE || policy(i) == POLICY_NEVER=>return policy(i) == POLICY_NEVER"
mutate never-visible "return policy(i) != POLICY_NEVER=>return true"
mutate state-ignored "    let s: u64 = e_state[i as usize] as u64=>    let s: u64 = STATE_UNSET"
mutate default-off-ignored "        return POLICY_OFF
    }=>        return POLICY_ON
    }"
mutate duplicates-allowed "|| find(p, n) != MAX_ENTRIES {=>{"
echo "AUTOSTART: $pass passed, $fail failed"
[ "$fail" = 0 ]
