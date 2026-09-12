#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/window.sh -- FENSTER, TASKLEISTE UND VOLLBILD WIE BEI WINDOWS
#
#   bash tools/design/window.sh
#
# Justins Korrektur, woertlich: "in Windows koennen die Fenster auch
# nicht ueber die Taskleiste geschoben werden, ich hatte dir aber
# gesagt das soll so sein, das war mein Fehler. Ist das jetzt so oder
# nicht? Bitte mach's so wie Windows."
#
# GEMESSEN WIRD NICHT, OB DAS ZIEHEN GEBLOCKT WIRD -- Windows blockt
# nicht. Windows laesst das Fenster unter die Leiste rutschen und haelt
# die Leiste OBENAUF. Drei Zahlenfragen, jede einzeln belegt:
#
#   1. LEISTE OBENAUF: ein Fenster wird absichtlich unter die Leiste
#      gezogen. Die Leiste muss danach VOLLSTAENDIG sichtbar sein.
#      Belegt aus `wm: ebene` (Ebene der Leiste > Ebene des Fensters)
#      und aus dem Bild: das Leistenband muss dieselben Farben zeigen
#      wie vor dem Ziehen.
#   2. MAXIMIEREN endet an der ARBEITSFLAECHE: y+h eines maximierten
#      Fensters darf die Oberkante der Leiste nie ueberschreiten.
#   3. VOLLBILD (F11): ganzer Schirm, ueber der Leiste, ohne Schmuck --
#      und zurueck auf EXAKT die alte Geometrie.
#
# Die Zahlen kommen aus `wm: fen` und `wm: work`, das Bild aus QEMU.
set -uo pipefail
cd "$(dirname "$0")/../.."

W=${1:-/tmp/fenstermess}
BUILDD=${DESIGNBUILD:-/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)}

SW=3440
SH=1440

# --------------------------------------------------------- 1. bauen
# Dasselbe Rezept wie capture.sh -- nur Kern und Platte, kein Foto.
echo "== bauen =="
bash vendor/firn/fetch-firnc.sh > "$BUILDD/fetch.log" 2>&1 || {
    echo "FEHLGESCHLAGEN: fetch-firnc.sh"; tail -5 "$BUILDD/fetch.log"; exit 1; }
./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
    || { echo "FEHLGESCHLAGEN: der Kern baut nicht"; tail -25 "$BUILDD/k.log"; exit 1; }
echo "kernel $(stat -c%s "$BUILDD/k0.mb") Oktette"

# DIE PLATTE. Sie wird von `capture.sh` gebaut (mkfs.py mit ueber
# hundert Argumenten); dieses Rezept hier zu wiederholen hiesse, es
# zweimal pflegen zu muessen. Genommen wird die zuletzt gebaute --
# der Kern ist frisch, und nur im Kern steckt das, was diese Runde
# aendert. Fehlt sie, sagt das Werkzeug WELCHER Befehl sie herstellt,
# statt mit einer QEMU-Fehlermeldung zu enden.
WURZEL=${WURZEL:-}
if [ -z "$WURZEL" ]; then
    WURZEL=$(ls -t /tmp/*/disk.img 2>/dev/null | head -1 || true)
fi
if [ ! -s "$WURZEL" ]; then
    echo "FEHLGESCHLAGEN: keine Wurzelplatte gefunden"
    echo "  einmal 'bash tools/design/capture.sh' laufen lassen,"
    echo "  oder WURZEL=/pfad/zu/disk.img setzen"
    exit 1
fi
echo "platte $WURZEL ($(stat -c%s "$WURZEL") Oktette)"

rm -rf "$W"; mkdir -p "$W"
cp "$WURZEL" "$W/disk.img"

# ------------------------------------------------------ 2. Drehbuch
cp tools/design/fenster.txt "$W/drehbuch.txt"

APPEND="osum gfx disp fbres=${SW}x${SH} wm wig desk wmshell wmdauer herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=en usb hidgen modfs"
APPEND="$APPEND nosched noproc nofs"

qemu-system-x86_64 -kernel "$BUILDD/k0.mb" -m 2048 -append "$APPEND" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=$SW,yres=$SH,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
sleep 3
python3 tools/design/drive.py "$W/mon" "$W/serial.txt" "$W" \
    "$W/drehbuch.txt" > "$W/fahren.log" 2>&1 || true
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo
echo "== der Fahrer =="
sed 's/^/   /' "$W/fahren.log" | tail -25

echo
echo "== was der Fensterverwalter selbst gemeldet hat =="
grep -aE 'wm: (work|fen|ebene|voll)' "$W/serial.txt" | tail -30 | sed 's/^/   /'

echo
python3 tools/design/fenstermess.py "$W" "$SW" "$SH"
