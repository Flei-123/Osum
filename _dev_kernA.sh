#!/usr/bin/env bash
# TEMPORAERER LAEUFER DES MODULS `kern` -- nicht fuer die Abnahme.
# Der Abnahmelaeufer ist tools/wmplug/run.sh (Modul E). Diese Datei
# bootet nur den Kern dieses Moduls und legt die serielle Leitung ab.
set -u
IMG=${1:-/tmp/kern.img}
APPEND=${2:-"gfx wm wmhold wmplug plugtest nokbd nosched noproc nofs"}
OUT=${3:-/tmp/kernA/ser.txt}
rm -f "$OUT" /tmp/kernA/mon.sock
qemu-system-x86_64 -accel kvm -cpu host -kernel "$IMG" -m 256 \
    -append "$APPEND" -serial "file:$OUT" -display none -no-reboot \
    -vga std -global VGA.edid=off -monitor unix:/tmp/kernA/mon.sock,server,nowait \
    -drive file=/tmp/kernA/disk.img,format=raw,if=ide,index=0 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 &
QPID=$!
for _ in $(seq 1 60); do
    sleep 1
    grep -q "wm: hold" "$OUT" 2>/dev/null && break
    kill -0 $QPID 2>/dev/null || break
done
grep -E "wmplug|wm: selftest|wm: hold" "$OUT" | head -40
kill $QPID 2>/dev/null
wait $QPID 2>/dev/null
echo "exit=$?"
