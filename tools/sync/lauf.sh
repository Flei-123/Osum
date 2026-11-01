#!/usr/bin/env bash
set -uo pipefail
KERN=${1:?kern fehlt}
IMG=${2:?abbild fehlt}
SER=${3:?serielldatei fehlt}
SKRIPT=${4:?skript fehlt}
shift 4
: > "$SER"
ACCEL=${OSUM_QEMU_ACCEL:-tcg}
timeout "${SYNC_TIMEOUT:-300}" qemu-system-x86_64 -accel "$ACCEL" \
    -kernel "$KERN" -m "${SYNC_MEM:-512}" \
    -append "osum vfs nokbd script=sh $SKRIPT;exit" \
    -serial "file:$SER" -display none -no-reboot \
    -drive "file=$IMG,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
echo $?
