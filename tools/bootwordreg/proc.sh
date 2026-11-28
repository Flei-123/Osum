#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh

KERNEL=${KERNEL:?usage: KERNEL=<osum.mb> tools/bootwordreg/proc.sh}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
PROGS="sh cat echo sleep"

mkdir -p "$WORK/bin"
bash tools/sync/build.sh "$WORK/bin" 0 $PROGS > "$WORK/build.txt" 2>&1 || { echo "BUILD-FAILED"; tail -5 "$WORK/build.txt"; exit 1; }
printf 'sleep 6\necho ==BW==\ncat /proc/bootwords\necho ==END==\n' > "$WORK/s.sh"
bash tools/mkfsfi/mkfs.sh build "$WORK/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$WORK/bin/$p.elf"; done) \
    "/t/s.sh=$WORK/s.sh" > "$WORK/mkfs.txt" 2>&1 || { echo "MKFS-FAILED"; tail -3 "$WORK/mkfs.txt"; exit 1; }

timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$KERNEL" -m 512 -vga std \
    -append "osum vfs bus gfx wm wig desk wmshell wmdauer wigapp=/bin/sh,/t/s.sh wighalt=30 r3alle nokbd ${BW_WORDS:-}" \
    -serial "file:$WORK/o.txt" -display none -no-reboot \
    -drive "file=$WORK/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
qpid=$!
waited=0
while [ $waited -lt 150 ] && kill -0 "$qpid" 2>/dev/null && ! grep -qa '==END==' "$WORK/o.txt" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
done
kill "$qpid" 2>/dev/null
wait "$qpid" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$WORK/o.txt" | sed -n '/==BW==/,/==END==/p'
