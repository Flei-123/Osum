#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/acpihigh/run.sh -- the processor list must be found when the ACPI tables sit above the first gibibyte (HP: RSDP 0xb1ffe000).
# Run through heavy:  /root/jarvis/bin/heavy bash tools/acpihigh/run.sh      ACPIHIGH_BASE=<rev with the old parser>
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
BASE_REV=${ACPIHIGH_BASE:-791a80137}
D=$(mktemp -d)
trap 'git worktree remove --force "$D/base" >/dev/null 2>&1; rm -rf "$D"; kill $(jobs -p) 2>/dev/null' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ACCEL=$([ -e /dev/kvm ] && echo kvm || echo tcg)

boot() { # <kernel> <ram_mb> <out>
    timeout 45 qemu-system-x86_64 -accel "$ACCEL" -machine q35 -cpu Skylake-Client -smp 4 -kernel "$1" -m "$2" \
        -append "osum smpfrueh" -serial "file:$3" -display none -no-reboot >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$3" > "$3.txt"
}

python3 -I tools/acpihigh/hpmadt.py tools/acpihigh/hp-827d-apic.bin > "$D/hp.txt" \
    && [ "$(cat "$D/hp.txt")" = "enabled=4 ids=0,2,1,3 disabled=12" ] && ok "HP MADT fixture: 4 enabled (ids 0,2,1,3), 12 disabled" || bad "HP MADT fixture: $(cat "$D/hp.txt")"

bash tools/build-kernel.sh "$D/new.img" --stufe 0 > "$D/new.log" 2>&1 && ok "kernel builds" || { bad "kernel build"; tail -5 "$D/new.log"; }
git worktree add --detach "$D/base" "$BASE_REV" > "$D/wt.log" 2>&1
(cd "$D/base" && FIRNLIB="$D/base/lib" bash tools/build-kernel.sh "$D/old.img" --stufe 0 > "$D/old.log" 2>&1) && ok "baseline kernel builds ($BASE_REV)" || { bad "baseline build"; tail -5 "$D/old.log"; }

boot "$D/new.img" 1024 "$D/n1024"
boot "$D/new.img" 3072 "$D/n3072"
boot "$D/old.img" 3072 "$D/o3072"
grep -a -q 'smp: 4 of 4 online, madt=4, failed: none' "$D/n1024.txt" && ok "tables below 1 GiB: 4 of 4 online" || bad "tables below 1 GiB: not 4 of 4"
grep -a -q 'smp: 4 of 4 online, madt=4, failed: none' "$D/n3072.txt" && ok "tables above 1 GiB (3072 MiB): 4 of 4 online, madt=4" || bad "tables above 1 GiB: $(grep -a 'smp: cpus=' "$D/n3072.txt" | head -1)"
grep -a -q 'smp: cpus=4  acpi=1' "$D/n3072.txt" && ok "tables above 1 GiB: acpi valid" || bad "tables above 1 GiB: acpi not valid"
grep -a -q 'smp: cpus=1  acpi=0' "$D/o3072.txt" && ok "counter-proof: old parser counts 1 CPU above 1 GiB" || bad "counter-proof: old parser did not fail ($(grep -a 'smp: cpus=' "$D/o3072.txt" | head -1))"
echo
echo "ACPIHIGH: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
