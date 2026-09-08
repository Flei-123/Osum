#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sync/lauf.sh -- EIN Osum-Lauf, damit der Laeufer und die Hand
# denselben Befehl benutzen.
#
#   bash tools/sync/lauf.sh <kern> <abbild> <serielldatei> <skript> [qemu-args...]
#
# Das Abbild wird IN PLACE benutzt (der Aufrufer kopiert vorher, wenn er
# das Original behalten will) -- genau das ist der Punkt: was das System
# geschrieben hat, liest der Wirt danach mit `mkfs.py cat` heraus, und
# nicht aus einem Mitschnitt der seriellen Leitung.
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
