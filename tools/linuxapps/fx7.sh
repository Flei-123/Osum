#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir}
OUT=${2:?outdir}
mkdir -p "$OUT"
SOCK="$OUT/mon.sock"
mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1; }
(
    i=0
    until grep -qa 'wayd: window c=' "$OUT/ser.txt" 2>/dev/null; do sleep 2; i=$((i + 2)); [ "$i" -gt 1500 ] && exit 0; done
    j=0
    until grep -qa 'FXLOAD' "$OUT/ser.txt" 2>/dev/null || [ "$j" -ge "${FX7_LOADWAIT:-150}" ]; do sleep 2; j=$((j + 2)); done
    sleep 15
    for k in a b c; do mon "sendkey $k"; sleep 2; done
    sleep 5
    for k in pgdn pgdn pgdn end; do mon "sendkey $k"; sleep 3; done
    mon "mouse_move 60 40"; sleep 1; mon "mouse_button 1"; sleep 1; mon "mouse_button 0"; sleep 1
    for n in 1 2 3; do mon "mouse_move 0 0 1"; sleep 1; done
) &
DP=$!
trap 'kill $DP 2>/dev/null' EXIT
GUI=1 DONE=FX-END BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-1500} MEM=${MEM:-3072} \
    EXTRA="/etc/fx3.sh=$PWD/tools/linuxapps/guest-fx7-input.sh@755" \
    KARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace nic nip=10.0.2.15/24 ngw=10.0.2.2 script=sh /etc/fx.sh;exit" \
    QEMU_EXTRA="-netdev user,id=n0 -device e1000,netdev=n0" \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-fx3-boot.sh "$OUT"
