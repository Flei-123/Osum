#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/uhrwerk/uhrprobe.sh -- TICKT DIE UHR OHNE EINGABE?
#
# Der Unterschied zu `messen.sh`: dort geht es um die ZAHLEN auf der
# seriellen Leitung, hier um das BILD. Und zwar um genau die Frage, die
# Justin gestellt hat -- bewegen sich die ZIFFERN, wenn niemand die
# Maus anfasst?
#
# Deshalb wird nicht zweimal fotografiert, sondern SECHSMAL im Abstand
# von je drei Sekunden, und zwar ERST, wenn der Schreibtisch fertig
# aufgebaut ist. Zwei Bilder aus der Aufbauphase unterscheiden sich
# immer -- da malt noch alles zum ersten Mal, und ein Unterschied
# beweist dann gar nichts.
#
# Verglichen wird NUR DER STREIFEN, in dem die Uhr sitzt: die unteren
# Zeilen am rechten Rand. Aendert er sich von Bild zu Bild, laeuft die
# Uhr aus eigener Kraft. Aendert er sich nicht, steht sie -- und genau
# das ist Justins Foto.
#
#   bash tools/uhrwerk/uhrprobe.sh <baudir> <ergebnisdir> [smp] [n] [abstand]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

BAU=${1:?baudir fehlt}
ERG=${2:?ergebnisdir fehlt}
SMP=${3:-4}
N=${4:-6}
ABST=${5:-3}
BREITE=${UHR_W:-3440}
HOEHE=${UHR_H:-1440}
mkdir -p "$ERG"; rm -f "$ERG"/*.ppm "$ERG"/*.png

APP="modfs osum gfx fbres=${BREITE}x${HOEHE} wm wig desk wmshell wmdauer tafel herz tz=120 usb hidgen nosched noproc nofs"
SOCK="$ERG/mon.sock"; OUT="$ERG/seriell.txt"
rm -f "$OUT" "$SOCK"

( timeout $((N * ABST + 60)) $QEMU_X86 -cpu host -smp "$SMP" -m 2048 \
    -kernel "$BAU/kern.mb" -initrd "$BAU/root.img" -append "$APP" \
    -serial "file:$OUT" -display none -no-reboot -vga std -global VGA.vgamem_mb=64 \
    -device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 -device usb-mouse,bus=x0.0 \
    -monitor "unix:$SOCK,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$ERG/qemu.log" 2>&1 ) &
QPID=$!

# WARTEN, BIS DER SCHREIBTISCH STEHT. Die Leiste meldet ihre erste
# Pulszeile nach 200 Runden, also nach rund fuenf Sekunden Betrieb --
# dann ist alles einmal gemalt und was sich danach bewegt, bewegt sich
# im laufenden Betrieb.
i=0
while [ $i -lt 1600 ]; do
    grep -qa 'taskbar: round=' "$OUT" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.05; i=$((i+1))
done
sleep 4

schuss() {
    python3 - "$SOCK" "$ERG/$1.ppm" <<'PY' 2>/dev/null || true
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
time.sleep(0.25); s.recv(65536)
s.sendall(("screendump %s\n" % sys.argv[2]).encode()); time.sleep(1.0)
try: s.recv(65536)
except Exception: pass
s.close()
PY
}

# ============ UND JETZT WIRD NICHTS EINGEGEBEN. Keine Maus, keine
# Taste -- nur fotografiert.
for k in $(seq 1 "$N"); do
    schuss "b$k"
    echo "  Bild $k"
    [ "$k" -lt "$N" ] && sleep "$ABST"
done
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; rm -f "$SOCK"

python3 - "$ERG" "$N" <<'PY'
import sys, os
from PIL import Image
erg, n = sys.argv[1], int(sys.argv[2])
ims = []
for k in range(1, n + 1):
    f = os.path.join(erg, "b%d.ppm" % k)
    if os.path.exists(f) and os.path.getsize(f) > 0:
        ims.append((k, Image.open(f).convert("RGB")))
if len(ims) < 2:
    print("NEIN: zu wenige Bilder"); sys.exit(1)
W, H = ims[0][1].size
print("Bildgroesse: %dx%d, %d Bilder" % (W, H, len(ims)))

# Der Uhrstreifen: die unteren 90 Zeilen, rechte Haelfte. Die Leiste ist
# height=40 bei Skala 2, also 80 Zeilen; 90 gibt Rand.
box = (W // 2, H - 90, W, H)
def cut(im): return im.crop(box)

print("\n== DER UHRSTREIFEN (rechte Haelfte der Leiste) ==")
vor = None; wechsel = 0
for k, im in ims:
    c = cut(im)
    if vor is not None:
        pa, pb = vor.load(), c.load()
        d = sum(1 for y in range(c.size[1]) for x in range(c.size[0])
                if pa[x, y] != pb[x, y])
        mark = "ANDERS" if d else "gleich"
        if d: wechsel += 1
        print("  Bild %d -> %d: %7d Bildpunkte anders   %s" % (k - 1, k, d, mark))
    vor = c
    c.save(os.path.join(erg, "uhr-b%d.png" % k))

# Und der GANZE Schirm, als Gegenprobe: wenn sich der ganze Schirm
# aendert, malt etwas zu viel.
print("\n== DER GANZE SCHIRM (Gegenprobe gegen Vollbild-Malerei) ==")
vor = None
for k, im in ims:
    if vor is not None:
        pa, pb = vor.load(), im.load()
        d = sum(1 for y in range(0, H, 4) for x in range(0, W, 4)
                if pa[x, y] != pb[x, y]) * 16
        print("  Bild %d -> %d: ~%d Bildpunkte anders (%.2f%% des Schirms)"
              % (k - 1, k, d, 100.0 * d / (W * H)))
    vor = im

print("\nERGEBNIS: der Uhrstreifen hat sich in %d von %d Abstaenden geaendert."
      % (wechsel, len(ims) - 1))
if wechsel == 0:
    print("  >>> DIE UHR STEHT. Genau Justins Befund.")
else:
    print("  >>> DIE UHR LAEUFT OHNE EINGABE.")
PY
