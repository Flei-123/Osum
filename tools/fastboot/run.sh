#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/summary.sh
. tools/lib/pidkill.sh
. tools/lib/tmpdir.sh

TMPD=$(mktemp -d)
osum_tmp_guard "" "$TMPD"
summary_begin FASTBOOT
trap 'summary_guard; rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

KERNEL=${KERNEL:?usage: KERNEL=<osum.mb> tools/fastboot/run.sh}
BASE_WORDS="osum nokbd noproc nofs noring3"
DONE_LINE='^smp: gs-basis'

boot() {
    local name=$1 cpus=$2 words=$3 log="$TMPD/$1.txt" pid i
    rm -f "$log"
    $QEMU_X86 -kernel "$KERNEL" -m 256 -smp "$cpus" -append "$BASE_WORDS $words" \
        -serial "file:$log" -display none -no-reboot >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 300); do
        grep -aq "$DONE_LINE" "$log" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    osum_kill_tree "$pid"
    wait "$pid" 2>/dev/null
}

has() { grep -aq "$2" "$TMPD/$1.txt"; }
tick_count() { sed -n 's/^ticks: \([0-9][0-9]*\)  traps=.*/\1/p' "$TMPD/$1.txt" | head -1; }
done_tasks() { grep -ac '^task: pid=[0-9]*  kind=2 .*state=5 .*exit=40' "$TMPD/$1.txt"; }

for cpus in 2 4; do
    boot "slow$cpus" "$cpus" ""
    boot "fast$cpus" "$cpus" "fastboot"
    boot "near$cpus" "$cpus" "fastbootx"

    has "slow$cpus" "$DONE_LINE" && ok "smp $cpus: baseline boot completed" || bad "smp $cpus: baseline boot did not complete"
    [ "$(tick_count slow$cpus)" -ge 20 ] 2>/dev/null && ok "smp $cpus: baseline waits for 20 ticks" || bad "smp $cpus: baseline tick count '$(tick_count slow$cpus)'"
    has "slow$cpus" '^spin: ticks=' && ok "smp $cpus: baseline runs the spin test" || bad "smp $cpus: baseline has no spin line"
    has "slow$cpus" '^smp: bench ' && has "slow$cpus" '^smp: stress ' && has "slow$cpus" '^smp: frames ' \
        && ok "smp $cpus: baseline runs the smp measurement suite" || bad "smp $cpus: baseline smp suite missing"

    has "fast$cpus" "$DONE_LINE" && ok "smp $cpus: fastboot boot completed" || bad "smp $cpus: fastboot boot did not complete"
    t=$(tick_count "fast$cpus")
    [ -n "$t" ] && [ "$t" -ge 2 ] && [ "$t" -le 8 ] && ok "smp $cpus: fastboot waits for few ticks ($t)" || bad "smp $cpus: fastboot tick count '$t'"
    has "fast$cpus" '^spin: ticks=' && bad "smp $cpus: fastboot ran the spin test" || ok "smp $cpus: fastboot skips the spin test"
    has "fast$cpus" '^smp: bench \|^smp: stress \|^smp: frames \|^smp: sched ' && bad "smp $cpus: fastboot ran the smp suite" || ok "smp $cpus: fastboot skips the smp suite"
    has "fast$cpus" "^smp: online=$cpus of $cpus  failed=0" && ok "smp $cpus: all cores online" || bad "smp $cpus: cores missing"
    has "fast$cpus" '^smp: locks ' && ok "smp $cpus: lock check still runs" || bad "smp $cpus: lock check missing"
    [ "$(done_tasks fast$cpus)" -ge 3 ] && ok "smp $cpus: scheduler tasks finished" || bad "smp $cpus: scheduler tasks unfinished ($(done_tasks fast$cpus))"
    has "fast$cpus" 'EXCEPTION\|kernel halted\|panic:' && bad "smp $cpus: fault line" || ok "smp $cpus: no fault line"

    [ "$(tick_count near$cpus)" -ge 20 ] 2>/dev/null && ok "smp $cpus: 'fastbootx' does not enable fastboot" || bad "smp $cpus: 'fastbootx' enabled fastboot"
done

summary_emit "$pass" "$fail" 26
