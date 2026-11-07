#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/summary.sh
summary_begin KSTATEAUDIT
trap summary_guard EXIT
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"; summary_guard' EXIT
pass=0
fail=0
check() {
    if [ "$1" = ok ]; then
        echo "OK    $2"
        pass=$((pass + 1))
    else
        echo "FAIL  $2"
        fail=$((fail + 1))
    fi
}

scan() {
    python3 -I "$ROOT/tools/kstateaudit/scan.py" "$1" 2>&1
}

scratch() {
    rm -rf "$WORK/$1"
    mkdir -p "$WORK/$1"
    cp -a kernel "$WORK/$1/kernel"
}

expect_red() {
    local name=$1 needle=$2 out
    out=$(scan "$WORK/$name")
    if [ $? -ne 0 ] && echo "$out" | grep -q -- "$needle"; then
        check ok "counter-proof $name: planted double base detected"
    else
        check bad "counter-proof $name: planted double base NOT detected"
    fi
}

out=$(scan "$ROOT")
if [ $? -eq 0 ]; then
    check ok "tree: no absolute address helper feeds a state-relative accessor ($(echo "$out" | tail -1))"
else
    check bad "tree: double state base found"
    echo "$out" | sed 's/^/        /'
fi

scratch control
out=$(scan "$WORK/control")
[ $? -eq 0 ] && check ok "counter-proof control: unplanted copy is green" || check bad "control copy is red"

scratch lockat
sed -i 's|return kstate.FLOCK_OFF + i \* kstate.FLOCK_BYTES|return state + kstate.FLOCK_OFF + i * kstate.FLOCK_BYTES|' "$WORK/lockat/kernel/sys/syslock.fi"
expect_red lockat "syslock.fi:.*via off"

scratch direct
printf '\nfn planted_at(state: u64, i: u64) -> u64 {\n    return state + kstate.FS_OFF + i * 8\n}\n\nfn planted_read(state: u64, i: u64) -> u64 {\n    return kstate.get(state, planted_at(state, i))\n}\n' >> "$WORK/direct/kernel/sys/syslock.fi"
expect_red direct "planted_at"

scratch viavar
printf '\nfn planted_at(state: u64, i: u64) -> u64 {\n    return state + kstate.FS_OFF + i * 8\n}\n\nfn planted_write(state: u64, i: u64) {\n    let p: u64 = planted_at(state, i)\n    kstate.set(state, p + 8, 1)\n}\n' >> "$WORK/viavar/kernel/sys/syslock.fi"
expect_red viavar "via p"

summary_emit "$pass" "$fail" 5
