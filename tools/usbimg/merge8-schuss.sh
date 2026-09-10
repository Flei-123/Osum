#!/usr/bin/env bash
# MERGE-8: das fertige Stick-Abbild in QEMU starten (3440x1440) und
# OHNE JEDE EINGABE zwei Bilder machen: eines sofort nach dem
# Schreibtisch, eines 90 s spaeter. Die Uhr in der Leiste muss dazwischen
# weitergelaufen sein (UHRWERK-Fix).
set -u
IMG=${1:?abbild fehlt}
ERG=${2:-/tmp/m8-schuss}
mkdir -p "$ERG"
QEMU=${QEMU_X86:-qemu-system-x86_64}
SOCK="$ERG/mon.sock"
SER="$ERG/seriell.txt"
rm -f "$SOCK" "$SER" "$ERG"/*.ppm "$ERG"/*.png

# -vga std mit viel vgamem: 3440x1440x32 sind 19,8 MiB Bildspeicher.
# KVM, damit die Uhr in Echtzeit laeuft (darum geht es hier).
$QEMU -m 2048 -smp 4 -enable-kvm -cpu host \
    -drive "file=$IMG,format=raw,if=ide,index=0" \
    -vga std -global VGA.vgamem_mb=64 \
    -device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 -device usb-mouse,bus=x0.0 \
    -serial "file:$SER" -display none -no-reboot \
    -monitor "unix:$SOCK,server,nowait" >/dev/null 2>&1 &
QPID=$!

mon() { # ein Monitorbefehl
    python3 - "$SOCK" "$1" <<'PY'
import socket,sys,time
s=socket.socket(socket.AF_UNIX); 
for _ in range(60):
    try: s.connect(sys.argv[1]); break
    except Exception: time.sleep(0.5)
else: sys.exit(1)
time.sleep(0.3); s.recv(65536)
s.sendall((sys.argv[2]+"\n").encode()); time.sleep(1.0)
try: print(s.recv(65536).decode(errors="replace"))
except Exception: pass
s.close()
PY
}

# Auf den Schreibtisch warten (die Leiste meldet ihre Runden seriell).
i=0
while [ $i -lt 2400 ]; do
    grep -qa 'taskbar: round=\|desk: start' "$SER" 2>/dev/null && break
    kill -0 $QPID 2>/dev/null || break
    sleep 0.25; i=$((i+1))
done
echo "== Schreibtisch nach $((i/4)) s =="
sleep 5
echo "== Bild 1 (0 s) =="
mon "screendump $ERG/schuss-0s.ppm" >/dev/null
echo "== 90 s warten, KEINE Eingabe =="
sleep 90
echo "== Bild 2 (90 s) =="
mon "screendump $ERG/schuss-90s.ppm" >/dev/null
sleep 2
kill $QPID 2>/dev/null; wait $QPID 2>/dev/null
for f in "$ERG"/*.ppm; do
    [ -e "$f" ] || continue
    python3 -c "
from PIL import Image; import sys
im=Image.open(sys.argv[1]); im.save(sys.argv[1][:-4]+'.png')
print(sys.argv[1][:-4]+'.png', im.size)
" "$f"
done
echo "== seriell (letzte Zeilen) =="; tail -5 "$SER"
