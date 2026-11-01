#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)

BAU=${1:?baudir fehlt}
ERG=${2:?ergebnisdir fehlt}
SEK=${3:-90}
SMP=${4:-4}
BREITE=${UHR_W:-3440}
HOEHE=${UHR_H:-1440}
mkdir -p "$ERG"

APP="modfs osum gfx fbres=${BREITE}x${HOEHE} wm wig desk wmshell wmdauer tafel herz tz=120 usb hidgen nosched noproc nofs"

SOCK="$ERG/mon.sock"
OUT="$ERG/seriell.txt"
rm -f "$OUT" "$SOCK" "$ERG/rc"

echo "== run: ${SEK}s, -smp $SMP, ${BREITE}x${HOEHE}, NO INPUT =="
( timeout $((SEK + 20)) $QEMU_X86 -cpu host -smp "$SMP" -m 2048 \
    -kernel "$BAU/kern.mb" -initrd "$BAU/root.img" -append "$APP" \
    -serial "file:$OUT" -display none -no-reboot \
    -vga std -global VGA.vgamem_mb=64 \
    -device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 -device usb-mouse,bus=x0.0 \
    -monitor "unix:$SOCK,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$ERG/qemu.log" 2>&1
  echo $? > "$ERG/rc" ) &
QPID=$!

i=0
while [ $i -lt 1200 ]; do
    grep -qa 'osum ' "$OUT" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.05; i=$((i+1))
done
sleep 3

schuss() { # name
    python3 - "$SOCK" "$ERG/$1.ppm" <<'PY' 2>/dev/null || true
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
time.sleep(0.3); s.recv(65536)
s.sendall(("screendump %s\n" % sys.argv[2]).encode()); time.sleep(1.2)
try: s.recv(65536)
except Exception: pass
s.close()
PY
}

echo "-- Bild 1 (Anfang) --"
schuss anfang
A_MARKE=$(date +%s)

sleep "$SEK"

echo "-- Bild 2 (Ende) --"
schuss ende
kill "$QPID" 2>/dev/null
wait "$QPID" 2>/dev/null

z0() { grep -a ' B[0-9]* T[0-9]*' "$OUT" | sed -n "$1p"; }
feld() { sed -n "s/.*[ ]$2\([0-9]\+\).*/\1/p" <<<"$1"; }
takt() { grep -a '8 TAKT' "$OUT" | sed -n "$1p"; }
tfeld() { sed -n "s/.* $2 \([0-9]\+\).*/\1/p" <<<"$1"; }

Z_A=$(z0 1); Z_E=$(z0 '$')
T_A=$(takt 1); T_E=$(takt '$')

B_A=$(feld "$Z_A" B); B_E=$(feld "$Z_E" B)
T_TA=$(feld "$Z_A" T); T_TE=$(feld "$Z_E" T)
L_A=$(tfeld "$T_A" LOOP); L_E=$(tfeld "$T_E" LOOP)
I_A=$(tfeld "$T_A" IRQ); I_E=$(tfeld "$T_E" IRQ)
PRE=$(tfeld "$T_E" PRE); HZ=$(tfeld "$T_E" HZ)

R_A=$(grep -a 'taskbar: round=' "$OUT" | head -1 | sed -n 's/.*round=\([0-9]*\).*/\1/p')
R_E=$(grep -a 'taskbar: round=' "$OUT" | tail -1 | sed -n 's/.*round=\([0-9]*\).*/\1/p')
SB_E=$(grep -a 'taskbar: round=' "$OUT" | tail -1 | sed -n 's/.*sb=\([0-9]*\).*/\1/p')
SBT_E=$(grep -a 'taskbar: round=' "$OUT" | tail -1 | sed -n 's/.*sbt=\([0-9]*\).*/\1/p')
PX_E=$(grep -a 'taskbar: round=' "$OUT" | tail -1 | sed -n 's/.*px=\([0-9]*\).*/\1/p')

d() { local a=${1:-0} b=${2:-0}; echo $(( ${b:-0} - ${a:-0} )); }

{
echo "=================================================="
echo "CLOCKWORK MEASUREMENT  ${SEK}s without any input, -smp $SMP"
echo "=================================================="
echo "PREEMPT (Soll 1) .................. ${PRE:-?}"
echo "HZ      (Soll 100) ................ ${HZ:-?}"
echo "TICKS   ${T_TA:-?} -> ${T_TE:-?}   (+$(d "$T_TA" "$T_TE"))"
echo "IRQ     ${I_A:-?} -> ${I_E:-?}   (+$(d "$I_A" "$I_E"))"
echo "LOOP    ${L_A:-?} -> ${L_E:-?}   (+$(d "$L_A" "$L_E"))"
echo "--------------------------------------------------"
echo "COMPOSES WITHOUT INPUT (the core number)"
echo "  wm.composites  ${B_A:-?} -> ${B_E:-?}   (+$(d "$B_A" "$B_E"))"
echo "--------------------------------------------------"
echo "TASKLEISTE (Ring 3)"
echo "  round   ${R_A:-?} -> ${R_E:-?}   (+$(d "$R_A" "$R_E"))"
echo "  status_build gerufen .... ${SB_E:-?}"
echo "  davon true (Bild neu) ... ${SBT_E:-?}"
echo "  Bildpunkte geschoben .... ${PX_E:-?}"
echo "=================================================="
} | tee "$ERG/bericht.txt"

if [ -f "$ERG/anfang.ppm" ] && [ -f "$ERG/ende.ppm" ]; then
    if cmp -s "$ERG/anfang.ppm" "$ERG/ende.ppm"; then
        echo "IMAGE: IDENTICAL -- the screen stands still." | tee -a "$ERG/bericht.txt"
    else
        echo "IMAGE: different -- something moved." | tee -a "$ERG/bericht.txt"
    fi
    for f in anfang ende; do
        python3 -c "
from PIL import Image
Image.open('$ERG/$f.ppm').save('$ERG/$f.png')" 2>/dev/null || true
    done
fi
rm -f "$SOCK"
