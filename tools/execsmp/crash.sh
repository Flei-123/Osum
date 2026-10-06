#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/execsmp/crash.sh -- r378: HOW OFTEN DOES THE KERNEL FALL OVER IN THE SPAWN VARIANT?
#
#   bash tools/execsmp/crash.sh [<boots>] [<cores>] [<extra kernel words>]
#
# Boots <boots> times (KVM when there is one) with `smpfrueh`, runs the spawn
# variant of `execsmp` (two runs at once) and counts the boots that end in a
# kernel exception or without the "execsmp: done" lines. Prints the lines of
# the first crash. Used to measure r378 before and after a fix.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
BOOTS=${1:-20}; CORES=${2:-4}; EXTRA=${3:-}
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
T=${CRASH_DIR:-$(mktemp -d)}; mkdir -p "$T/bin"
[ -n "${CRASH_DIR:-}" ] || trap 'rm -rf "$T"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$T/bin" 0 sh echo execsmp > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
printf 'echo ==EXEC==\nexecsmp run spawn 1 2\nexecsmp run spawn 1 2\necho ==END==\n' > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/execsmp="$T/bin/execsmp.elf" /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
crash=0; first=""
for n in $(seq 1 "$BOOTS"); do
    cp -f "$T/d.img" "$T/r.img"
    timeout 300 qemu-system-x86_64 -accel "$ACC" -smp "$CORES" -kernel "$T/k0.img" -m 512 \
        -append "osum vfs nokbd smpfrueh $EXTRA script=sh /t/s.sh;exit" \
        -serial "file:$T/s$n.txt" -display none -no-reboot \
        -drive "file=$T/r.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/s$n.txt" > "$T/s$n.klar"
    if grep -aqE "EXCEPTION|panic|stack guard|ud2|DOUBLE" "$T/s$n.klar" || [ "$(grep -ac 'execsmp: children=' "$T/s$n.klar")" != 2 ]; then
        crash=$((crash+1)); [ -z "$first" ] && first=$n && cp "$T/s$n.klar" "${CRASH_KEEP:-/tmp/crash-first.txt}"
    fi
    rm -f "$T/s$n.txt"
done
echo "CRASH: $crash of $BOOTS boots ($CORES cores, $ACC, extra='$EXTRA')"
[ -n "$first" ] && grep -aE "EXCEPTION|panic|rip=|spur|rsp=" "${CRASH_KEEP:-/tmp/crash-first.txt}" | head -12
# r378: with the fix in `sched.schedule_locked` (next == cur sets S_RUN) this is 0
# of 30 (4 cores) and 0 of 20 (3 cores); without it 6 of 24 and 2 of 12.
[ "$crash" -eq 0 ]
