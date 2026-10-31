#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
OUT=${1:-/dev/stdout}
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$T/bin"
bash tools/sync/build.sh "$T/bin" 0 sh cat echo > "$T/b.txt" 2>&1 || { tail -15 "$T/b.txt"; exit 1; }
./tools/build-kernel.sh "$T/k0.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail -15 "$T/k.txt"; exit 1; }
printf 'echo ==VMXCAPS==\ncat /proc/vmxcaps\necho ==END==\n' > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 20000 /bin/ /t/ /tmp/ /proc/ /dev/ /etc/ /var/ \
    $(for p in sh cat echo; do echo "/bin/$p=$T/bin/$p.elf"; done) "/t/s.sh=$T/s.sh" > "$T/mkfs.txt" 2>&1 || tail -3 "$T/mkfs.txt"
CPUS=${HVPROBE_CPUS:-"qemu64 max"}
: > "$OUT"
for cpu in $CPUS; do
    ACC=tcg
    [ "$cpu" = host ] && ACC=kvm
    timeout 150 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k0.img" -m 512 -cpu "$cpu" \
        -append "osum vfs nokbd script=sh /t/s.sh;exit" \
        -serial "file:$T/o.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo "### cpu=$cpu accel=$ACC" >> "$OUT"
    tr -cd '\11\12\15\40-\176' < "$T/o.txt" | awk 'index($0,"==VMXCAPS=="){f=1;next} index($0,"==END=="){f=0} f' >> "$OUT"
done
