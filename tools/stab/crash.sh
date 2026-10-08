#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stab/crash.sh -- Dell stability: how often does the kernel fall over
# under fork/exit/wait4/kill churn?
#
#   bash tools/stab/crash.sh [boots] [cores] [rounds] [workers] [supervisors] [kernel words]
#
# Boots <boots> times (KVM when there is one), runs `stab run <rounds> <workers>
# <supervisors>` (kernel/user/stab.fi) and counts the boots that end in a kernel
# exception / stack guard / ud2 or without the final "stab: done" line.
# KTREE=<other worktree> builds the KERNEL from that tree (for before/after
# series against an older commit); the guest program always comes from this tree.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
BOOTS=${1:-10}; CORES=${2:-4}; ROUNDS=${3:-6}; WORKERS=${4:-8}; SUPS=${5:-3}; EXTRA=${6:-}
KTREE=${KTREE:-$ROOT}
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
T=${CRASH_DIR:-$(mktemp -d)}; mkdir -p "$T/bin"
[ -n "${CRASH_DIR:-}" ] || trap 'rm -rf "$T"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$T/bin" 0 sh echo stab > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
(cd "$KTREE" && FIRNLIB="$KTREE/lib" ./tools/build-kernel.sh "$T/k0.img" --stufe 0) > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
printf 'echo ==STAB==\nstab run %s %s %s\necho ==END==\n' "$ROUNDS" "$WORKERS" "$SUPS" > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/stab="$T/bin/stab.elf" /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
crash=0; incomplete=0; first=""; t0=$(date +%s)
for n in $(seq 1 "$BOOTS"); do
    cp -f "$T/d.img" "$T/r.img"
    timeout "${BOOT_TIMEOUT:-240}" qemu-system-x86_64 -accel "$ACC" -smp "$CORES" -kernel "$T/k0.img" -m 512 \
        -append "osum vfs nokbd smpfrueh $EXTRA script=sh /t/s.sh;exit" \
        -serial "file:$T/s$n.txt" -display none -no-reboot \
        -drive "file=$T/r.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/s$n.txt" > "$T/s$n.klar"
    if grep -aqE "EXCEPTION|panic|PANIK|stack guard|ud2|DOUBLE|KERNSTAPEL|lock: stuck" "$T/s$n.klar"; then
        crash=$((crash+1)); [ -z "$first" ] && first=$n && cp "$T/s$n.klar" "${CRASH_KEEP:-/tmp/stab-first.txt}"
    elif ! grep -aq "stab: done" "$T/s$n.klar"; then
        incomplete=$((incomplete+1)); [ -z "$first" ] && first=$n && cp "$T/s$n.klar" "${CRASH_KEEP:-/tmp/stab-first.txt}"
    fi
    rm -f "$T/s$n.txt"
done
echo "STAB: crashed=$crash incomplete=$incomplete of $BOOTS boots ($CORES cores, $ACC, ${ROUNDS}x${WORKERS}x${SUPS}, extra='$EXTRA', $(( $(date +%s)-t0 )) s)"
[ -n "$first" ] && grep -aE "EXCEPTION|panic|PANIK|rip=|spur|rsp=|stuck|KERNSTAPEL|ud2" "${CRASH_KEEP:-/tmp/stab-first.txt}" | head -12
[ "$crash" -eq 0 ] && [ "$incomplete" -eq 0 ]
