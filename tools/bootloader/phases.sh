#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
RUNS=${RUNS:-3}
BUS=${BUS:-ehci}
MACH=${MACH:-q35}
MARKS=${MARKS:-osboot|osboot: gunzip|osboot: start|osum: from module|glogin: rect}
D=$(mktemp -d /root/abbilder/osbootphase.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
osb_prepare "$D" || { echo "OSPHASE: prepare failed"; exit 1; }
IFS='|' read -ra MARK_LIST <<< "$MARKS"
phase_run() {
    local loader=$1 name=$2 img=$3
    cp "$img" "$D/$name.img"
    cp "$OSB_VARS" "$D/$name.vars"
    rm -f "$D/$name.txt"
    local t0 now
    t0=$(date +%s%N)
    timeout 150 qemu-system-x86_64 "${OSB_KVM[@]}" -machine "$MACH" -m 2048 -smp 2 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OSB_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$D/$name.vars" \
        -drive "file=$D/$name.img,format=raw,if=none,id=stick" $(osb_bus "$BUS") \
        -serial "file:$D/$name.txt" -display none -no-reboot -pidfile "$D/$name.pid" &
    declare -A seen=()
    local line="" i=0 last="${MARK_LIST[-1]}"
    while [ $i -lt 2400 ]; do
        for m in "${MARK_LIST[@]}"; do
            if [ -z "${seen[$m]:-}" ] && grep -aq "$m" "$D/$name.txt" 2>/dev/null; then
                now=$(date +%s%N); seen[$m]=$(( (now - t0) / 1000000 ))
            fi
        done
        [ -n "${seen[$last]:-}" ] && break
        sleep 0.05; i=$((i+1))
    done
    kill "$(cat "$D/$name.pid" 2>/dev/null)" 2>/dev/null; wait 2>/dev/null
    rm -f "$D/$name.img" "$D/$name.vars"
    for m in "${MARK_LIST[@]}"; do line="$line ${seen[$m]:--1}"; done
    echo "OSPHASE: $loader$line"
}
echo "OSPHASE: marks: ${MARKS//|/ | }"
for r in $(seq 1 "$RUNS"); do
    phase_run osboot "o$r" "$D/stick.img"
    phase_run limine "l$r" "$D/limine.img"
done
