#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/shot-gui.sh -- EIN FOTO VOM INSTALLATIONSFENSTER.
#
#   bash tools/install/shot-gui.sh <bauverzeichnis> <ausgabe.png> [args] [zielplatte]
#
# <bauverzeichnis> ist eines von `tools/usbimg/build.sh` (osum.mb +
# root.img). Die Zielplatte haengt als /dev/hda daran -- ohne sie hat
# das Fenster nichts zu zeigen, und genau das waere ein falsches Bild.
#
# ==================================================================
# WARUM `wigapp=` UND KEIN NEUES KERNWORT
# ==================================================================
#
# Runde POWERMON hat dafuer schon die richtige Stelle gebaut, und der
# Kommentar in `kernel/kgui.fi` sagt auch warum: ein viertes fest
# verdrahtetes `/bin/NAME` haette eine fuenfte Runde gebraucht, die ein
# fuenftes will. `wigapp=/bin/installer` startet dieses Programm im
# Fensterserver, ohne dass ein Bit in `kstate.MODE` dafuer draufgeht --
# und das Wort davor (`wig`) setzt M_WIG ohnehin.
#
# DER DAUERBETRIEB UND NICHT `wmhold`: mit `wmhold` ist die Schleife
# vorbei, bevor ein Monitorbefehl ankommt -- der Druck steht dann als
# letzte Zeile im Bericht und niemand liest ihn mehr. Das ist die Lehre
# aus tools/usbimg/shot-qs2.sh, Punkt 1, und sie wird hier nicht noch
# einmal neu gelernt.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

IMGDIR=${1:?bauverzeichnis fehlt}
OUT=${2:?ausgabe.png fehlt}
ARGS=${3:-}
ZIEL=${4:-}

[ -f "$IMGDIR/osum.mb" ] || { echo "== $IMGDIR/osum.mb fehlt" >&2; exit 1; }
[ -f "$IMGDIR/root.img" ] || { echo "== $IMGDIR/root.img fehlt" >&2; exit 1; }

W=$(mktemp -d)
QP=""
trap 'kill $QP 2>/dev/null; rm -rf "$W"' EXIT

# EINE EIGENE KOPIE DER ZIELPLATTE. Zwei Laeufe duerfen sich nicht um
# die Schreibsperre streiten ("Failed to get write lock"), und ein Foto
# soll die Platte nicht veraendern, die der naechste Lauf misst.
PLATTE=()
if [ -n "$ZIEL" ]; then
    cp "$ZIEL" "$W/ziel.img"
    PLATTE=(-drive "file=$W/ziel.img,format=raw,if=ide,index=0")
fi

APPEND="modfs osum gfx wm wig desk wmshell wmdauer herz nostart"
APPEND="$APPEND nosched noproc nofs lang=de uiscale=1"
# Die Argumente haengen mit KOMMA am Pfad -- so zerlegt sie
# `wigapp_zerlegen` in kernel/kgui.fi (jedes Komma wird zur Null).
if [ -n "$ARGS" ]; then
    APPEND="$APPEND wigapp=/bin/installer,$ARGS"
else
    APPEND="$APPEND wigapp=/bin/installer"
fi

timeout 300 $QEMU_X86 -m 512 \
    -kernel "$IMGDIR/osum.mb" -initrd "$IMGDIR/root.img" \
    -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$W/mon,server,nowait" \
    "${PLATTE[@]}" > "$W/qemu.log" 2>&1 &
QP=$!

mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1; sleep "${2:-1}"; }

# Warten, bis das Fenster WIRKLICH steht -- nicht nur der Kern.
#
# GEWARTET WIRD AUF DEN FENSTERSERVER UND NICHT AUF DAS PROGRAMM.
# Die erste Fassung hat hier auf die Zeile 'installer: ready' gewartet --
# Zeile, die das Programm selbst schreibt. Sie kam nie: die Ausgabe
# eines Programms, das der Schreibtisch startet, landet nicht auf der
# seriellen Leitung des Kerns. Gewartet wurde also 300 Sekunden lang
# auf etwas, das nicht kommen konnte, und das Bild entstand erst durch
# den Zeitablauf.
#
# Was der Kern SEHR WOHL meldet, ist jedes Fenster, das er malt
# (die Zeile 'wm: fen ... w=640 h=440'). Darauf laesst sich warten, und es
# ist die ehrlichere Bedingung: es steht genau dann da, wenn wirklich
# ein Fenster dieser Groesse gemalt wurde.
i=0
while [ $i -lt 400 ]; do
    grep -qa 'w=640 h=440' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i + 1))
done
sleep 6

mon "screendump $W/s.ppm" 4
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

mkdir -p "$(dirname "$OUT")"
cp "$W/serial.txt" "${OUT%.png}.txt" 2>/dev/null
if [ -s "$W/s.ppm" ]; then
    python3 -c "
from PIL import Image
Image.open('$W/s.ppm').save('$OUT')
print('  $OUT')
"
else
    echo "== kein Bild entstanden" >&2
    tail -5 "$W/qemu.log" >&2
    exit 1
fi
grep -aE '^installer:|w=640 h=440' "$W/serial.txt" | tail -6 | sed 's/^/      /'
