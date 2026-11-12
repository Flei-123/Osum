#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir}
OUT=${2:?outdir}
mkdir -p "$OUT/shots"
SOCK="$OUT/mon.sock"
(
    i=0
    until grep -qa 'FXLOAD' "$OUT/ser.txt" 2>/dev/null; do
        sleep 5; i=$((i + 5)); [ "$i" -gt "${FX13_MAXWAIT:-1500}" ] && break
        [ -S "$SOCK" ] && printf 'screendump %s/shots/pre-%04d.ppm\n' "$OUT" "$i" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1
        [ $((i % 30)) -ne 0 ] && rm -f "$OUT/shots/pre-$(printf %04d $((i - 5))).ppm"
    done
    for n in 1 2 3 4 5 6; do
        sleep 5; printf 'screendump %s/shots/post-%d.ppm\n' "$OUT" "$n" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1
    done
    sleep 3; printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1
) &
DP=$!
trap 'kill $DP 2>/dev/null' EXIT
GUI=1 DONE=FX-END BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-1600} MEM=${MEM:-3072} \
    KARGS="gfx disp wm wmdauer wmshell osum vfs bus fremdtrace nic nip=10.0.2.15/24 ngw=10.0.2.2 script=sh /etc/fx.sh;exit" \
    QEMU_EXTRA="-netdev user,id=n0 -device e1000,netdev=n0 -vga std" \
    EXTRA="/etc/fx3.sh=$PWD/tools/linuxapps/guest-fx13-page.sh@755" \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-fx3-boot.sh "$OUT"
