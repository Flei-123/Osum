#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0
fail=0
ok() { echo "  ok   $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL $1"; fail=$((fail + 1)); }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fresh_copy() {
    rm -rf "$scratch/t"
    mkdir -p "$scratch/t"
    cp -r kernel "$scratch/t/kernel"
    cp -r tools "$scratch/t/tools"
}

expect_fail() {
    local label=$1 needle=$2
    out=$(python3 -I tools/limits/check.py "$scratch/t" 2>&1)
    if [ $? -ne 0 ] && echo "$out" | grep -q "$needle"; then ok "$label"; else bad "$label: $out"; fi
}

echo "== 1. real tree: every per-task and per-CPU table follows kstate =="
out=$(python3 -I tools/limits/check.py . 2>&1)
if [ $? -eq 0 ]; then ok "$out"; else bad "$out"; fi

echo "== 2. counter-proofs =="
fresh_copy
sed -i 's/^const SLOTS: u64 = kstate.MAX_TASKS/const SLOTS: u64 = 256/' "$scratch/t/kernel/sched/ptstate.fi"
expect_fail "ptstate SLOTS back at 256 is caught" "ptstate.fi: const SLOTS"

fresh_copy
sed -i 's/\[u64; 9216\] = \[0 as u64; 9216\]/[u64; 4608] = [0 as u64; 4608]/' "$scratch/t/kernel/sched/ptstate.fi"
expect_fail "ptstate table at 256 tasks is caught" "array table has 4608"

fresh_copy
sed -i 's/^const MAX_CPUS: u64 = kstate.MAX_CPUS/const MAX_CPUS: u64 = 8/' "$scratch/t/kernel/mm/framedefer.fi"
expect_fail "an independent MAX_CPUS literal is caught" "framedefer.fi: const MAX_CPUS"

fresh_copy
sed -i 's/^static mut armed: \[u64; 512\] = \[0 as u64; 512\]/static mut armed: [u64; 256] = [0 as u64; 256]/' "$scratch/t/kernel/sched/sigsysinfo.fi"
expect_fail "a short per-task array is caught" "array armed has 256"

fresh_copy
sed -i 's/^const MAX_TASKS: u64 = 512/const MAX_TASKS: u64 = 1024/' "$scratch/t/kernel/lib/kstate.fi"
expect_fail "raising MAX_TASKS without the tables is caught" "MAX_TASKS"

fresh_copy
printf 'static mut extra_wake: [u64; 512] = [0 as u64; 512]\n' >> "$scratch/t/kernel/sched/hrt.fi"
expect_fail "an unlisted table in a listed file is caught" "extra_wake"

fresh_copy
printf 'const MAX_CPUS: u64 = 8\n' > "$scratch/t/kernel/diag/newcpu.fi"
expect_fail "a new file with its own MAX_CPUS is caught" "newcpu.fi"

echo "LIMITS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
