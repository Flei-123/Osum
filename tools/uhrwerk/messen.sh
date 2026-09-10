#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/uhrwerk/messen.sh -- LAEUFT DAS BILD OHNE EINGABE WEITER?
#
# ==================================================================
# DIE FRAGE, UND WARUM SIE OHNE EINGABE GESTELLT WIRD
# ==================================================================
#
# Justin hat auf echtem Blech fotografiert: die Uhr in der Taskleiste
# steht. Faehrt er mit der MAUS ueber die Ziffern, springt sie auf die
# richtige Zeit. Maus woanders bewegen reicht nicht.
#
# Das ist die Beschreibung eines Bildschirms, der nur dort und nur dann
# aufgefrischt wird, wo Eingabe passiert -- und die Gegenprobe dazu ist
# ein Lauf, in dem NIEMAND etwas eingibt. Kein `mouse_move`, kein
# `sendkey`, nichts. Was sich in diesem Lauf bewegt, bewegt sich aus
# eigener Kraft.
#
# GEMESSEN WIRD AUS DER SERIELLEN LEITUNG, in Zahlen und nicht im Bild:
#
#   B=    wm.composites  -- wie oft das Bild ZUSAMMENGESETZT wurde. Das
#         ist die Kernzahl. Ohne Eingabe muss sie steigen, sonst kommt
#         nichts auf den Schirm.
#   T=    kstate.TICKS   -- schlaegt der Zeitgeber ueberhaupt?
#   LOOP= tafel_loop     -- laeuft die Schreibtischschleife?
#   IRQ=  tafel_irq      -- Rufe aus dem Zeitgeber
#   PRE=  kstate.PREEMPT -- ist die Verdraengung an? (Soll 1)
#   HZ=   die gemessene Rate (Soll 100)
#   R=    taskbar: round -- laeuft die Ring-3-Schleife der Leiste?
#   SB=   status_build-Rufe / SBT= davon `true`
#
# Und dazu zwei Bilder, am Anfang und am Ende. Steht in beiden dieselbe
# Uhrzeit, ist das Bild eingefroren -- egal was die Zahlen sagen.
#
#   bash tools/uhrwerk/messen.sh <baudir> <ergebnisdir> [sekunden] [smp]
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

# GENAU DIE ZEILE DES STICKS (tools/usbimg/build.sh, Eintrag 1) -- ohne
# `nopuls`, weil der Puls hier das Messgeraet ist, und mit `tafel`,
# weil die Tafelzeilen die Zahlen tragen.
APP="modfs osum gfx fbres=${BREITE}x${HOEHE} wm wig desk wmshell wmdauer tafel herz tz=120 usb hidgen nosched noproc nofs"

SOCK="$ERG/mon.sock"
OUT="$ERG/seriell.txt"
rm -f "$OUT" "$SOCK" "$ERG/rc"

echo "== Lauf: ${SEK}s, -smp $SMP, ${BREITE}x${HOEHE}, KEINE EINGABE =="
( timeout $((SEK + 20)) $QEMU_X86 -cpu host -smp "$SMP" -m 2048 \
    -kernel "$BAU/kern.mb" -initrd "$BAU/root.img" -append "$APP" \
    -serial "file:$OUT" -display none -no-reboot \
    -vga std -global VGA.vgamem_mb=64 \
    -device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 -device usb-mouse,bus=x0.0 \
    -monitor "unix:$SOCK,server,nowait" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$ERG/qemu.log" 2>&1
  echo $? > "$ERG/rc" ) &
QPID=$!

# Auf die erste Tafelzeile warten -- ab da laeuft der Schreibtisch.
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

# ============ UND JETZT PASSIERT NICHTS. Das ist der Versuch.
sleep "$SEK"

echo "-- Bild 2 (Ende) --"
schuss ende
kill "$QPID" 2>/dev/null
wait "$QPID" 2>/dev/null

# ---- die Zahlen aus der seriellen Leitung ----
# Zeile 0 der Tafel: "<fassung> B<composites> T<ticks> sh<n>"
# Zeile 8:           "8 TAKT  IRQ <n> MAL <n> LOOP <n> PRE <n> HZ <n>"
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
echo "UHRWERK-MESSUNG  ${SEK}s ohne jede Eingabe, -smp $SMP"
echo "=================================================="
echo "PREEMPT (Soll 1) .................. ${PRE:-?}"
echo "HZ      (Soll 100) ................ ${HZ:-?}"
echo "TICKS   ${T_TA:-?} -> ${T_TE:-?}   (+$(d "$T_TA" "$T_TE"))"
echo "IRQ     ${I_A:-?} -> ${I_E:-?}   (+$(d "$I_A" "$I_E"))"
echo "LOOP    ${L_A:-?} -> ${L_E:-?}   (+$(d "$L_A" "$L_E"))"
echo "--------------------------------------------------"
echo "COMPOSES OHNE EINGABE (die Kernzahl)"
echo "  wm.composites  ${B_A:-?} -> ${B_E:-?}   (+$(d "$B_A" "$B_E"))"
echo "--------------------------------------------------"
echo "TASKLEISTE (Ring 3)"
echo "  round   ${R_A:-?} -> ${R_E:-?}   (+$(d "$R_A" "$R_E"))"
echo "  status_build gerufen .... ${SB_E:-?}"
echo "  davon true (Bild neu) ... ${SBT_E:-?}"
echo "  Bildpunkte geschoben .... ${PX_E:-?}"
echo "=================================================="
} | tee "$ERG/bericht.txt"

# Die beiden Bilder unterscheiden sich? Dann hat sich etwas bewegt.
if [ -f "$ERG/anfang.ppm" ] && [ -f "$ERG/ende.ppm" ]; then
    if cmp -s "$ERG/anfang.ppm" "$ERG/ende.ppm"; then
        echo "BILD: IDENTISCH -- der Schirm steht still." | tee -a "$ERG/bericht.txt"
    else
        echo "BILD: unterschiedlich -- etwas hat sich bewegt." | tee -a "$ERG/bericht.txt"
    fi
    for f in anfang ende; do
        python3 -c "
from PIL import Image
Image.open('$ERG/$f.ppm').save('$ERG/$f.png')" 2>/dev/null || true
    done
fi
rm -f "$SOCK"
