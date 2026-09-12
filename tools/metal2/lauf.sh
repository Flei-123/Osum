#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/metal2/lauf.sh -- EIN SCHREIBTISCHLAUF MIT USB-MAUS UND QMP-STROM.
#
#   bash tools/metal2/lauf.sh <ausgabeverzeichnis> <osum.mb> <root.img> \
#        <sekunden> <hz> "<zusatz-bootwoerter>" [maus.py-optionen...]
#
# Startet den Kern unter QEMU/KVM auf 3440x1440 (fbres=) mit
# `fbpad=16` (gemeldete Breite 3424 bei Zeilenbreite 13760 -- der Fall
# echter Firmware), einem xHCI-Regler mit USB-Tastatur und USB-Maus,
# wartet, bis die Taskleiste steht, laesst tools/metal2/maus.py den
# Bewegungsstrom fahren, fotografiert, und legt ab:
#
#   <aus>/serial.txt   die serielle Leitung (mit `tafel:`-Zeilen)
#   <aus>/maus.txt     was maus.py gesendet hat
#   <aus>/shot.ppm/png das Bild am Ende
#   <aus>/tafel.txt    der LETZTE vollstaendige Tafelanstrich
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

AUS=${1:?ausgabeverzeichnis}
KERN=${2:?osum.mb}
ROOT=${3:?root.img}
SEK=${4:-60}
HZ=${5:-1000}
ZUSATZ=${6:-}
if [ $# -ge 6 ]; then shift 6; else shift $#; fi
MAUSOPT="$*"
mkdir -p "$AUS"
rm -f "$AUS/serial.txt" "$AUS/qmp.sock" "$AUS/shot.ppm" "$AUS/rc"

BASE="modfs osum gfx fbres=3440x1440 fbpad=16 wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nosched noproc nofs"
CMD="$BASE $ZUSATZ"
GESAMT=$(( SEK + 150 ))

( timeout "$GESAMT" $QEMU_X86 -kernel "$KERN" -initrd "$ROOT" -m 1024 \
    -append "$CMD" -serial "file:$AUS/serial.txt" -display none -no-reboot \
    -device VGA,edid=off,vgamem_mb=64 \
    -device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 -device usb-mouse,bus=x0.0 \
    -qmp "unix:$AUS/qmp.sock,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$AUS/qemu.txt" 2>&1
  echo $? > "$AUS/rc" ) &
QPID=$!

# warten, bis die Leiste steht (oder 60 s)
i=0
while [ $i -lt 1200 ]; do
    grep -qa 'taskbar: STEHT' "$AUS/serial.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.05; i=$((i+1))
done
sleep 2
python3 tools/metal2/maus.py "$AUS/qmp.sock" "$SEK" "$HZ" \
    shot="$AUS/shot.ppm" $MAUSOPT > "$AUS/maus.txt" 2>&1
cat "$AUS/maus.txt"
# noch einen Puls abwarten, damit die Tafel nach dem Strom gesagt wird
sleep 6
# QEMU beenden
python3 - "$AUS/qmp.sock" <<'PY' 2>/dev/null
import json, socket, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(3)
try:
    s.connect(sys.argv[1]); f = s.makefile("rb"); f.readline()
    s.sendall(b'{"execute":"qmp_capabilities"}\n'); f.readline()
    s.sendall(b'{"execute":"quit"}\n')
except Exception as e:
    pass
PY
sleep 1
kill "$QPID" 2>/dev/null
wait "$QPID" 2>/dev/null

if [ -f "$AUS/shot.ppm" ]; then
    python3 tools/gfx/ppm2png.py "$AUS/shot.ppm" "$AUS/shot.png" >/dev/null 2>&1 \
        || python3 -c "from PIL import Image; Image.open('$AUS/shot.ppm').save('$AUS/shot.png')"
fi
# der letzte vollstaendige Anstrich: ab der letzten Zeile '1 ' bis zum Ende
grep -a '^tafel: ' "$AUS/serial.txt" | sed 's/^tafel: //' > "$AUS/tafel-alle.txt"
# je Zeilennummer der LETZTE Stand (Zeile 0 traegt keine Nummer und faellt weg)
awk '{ if ($1 ~ /^[0-9]+$/) { k = $1 + 0; z[k] = $0; if (k > m) m = k } } END { for (i = 0; i <= m; i++) if (i in z) print z[i] }' "$AUS/tafel-alle.txt" > "$AUS/tafel.txt"
echo "== letzter Tafelanstrich =="
cat "$AUS/tafel.txt"
echo "== eingabe (letzter Puls) =="
grep -a 'eingabe:' "$AUS/serial.txt" | tail -1 | sed 's/.*eingabe:/eingabe:/'
echo "== wm: fen (Terminal) =="
grep -a '^wm: fen i=0 ' "$AUS/serial.txt" | tail -1
echo "rc=$(cat "$AUS/rc" 2>/dev/null)"
