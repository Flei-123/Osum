#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotplug/bild-term.sh -- DIE BILDER: DER STICK IM TERMINALFENSTER.
#
#   bash tools/hotplug/bild-term.sh [ausgabeverzeichnis]
#
# WARUM NICHT IM DATEIMANAGER: der stirbt in diesem Baum beim Aufbau
# seiner Seitenleiste, und zwar SEIT VOR DIESER RUNDE -- die Gegenprobe
# mit dem unveraenderten `explorer.fi` aus `main` stirbt genauso
# (docs/HOTPLUG.md, "Ein bestehender Fehler"). Ein Bild von einem
# Programm, das nicht laeuft, gibt es nicht.
#
# Was stattdessen fotografiert wird, ist derselbe Weg eine Schicht
# tiefer und auf demselben Schreibtisch: eine SHELL IM FENSTER
# (`wmshell`), in der `auswerfen` laeuft -- dasselbe Programm, dasselbe
# Aufruf 1704, dieselbe Tafel des Kerns, die auch die Seitenleiste
# liest. Drei Bilder aus EINER laufenden Maschine:
#
#   10-vorher.png   `auswerfen` sagt: kein Wechseldatentraeger da
#   20-steckt.png   nach dem Anstecken: /medien/usb0 mit Groesse
#   30-danach.png   nach dem Auswerfen: wieder leer
#
# Der UNTERSCHIED zwischen den dreien ist die Zusage. Ein einzelnes
# Bild mit einer Zeile darauf koennte immer dagestanden haben.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

AUS=${1:-docs/shots/hotplug}
mkdir -p "$AUS"
ARB=${HP_ARB:-$(mktemp -d)}
mkdir -p "$ARB"
[ -n "${HP_ARB:-}" ] || trap 'rm -rf "$ARB"' EXIT

PROGS="sh echo ls cat auswerfen mount sleep"

echo "== bauen =="
./tools/build-kernel.sh "$ARB/k.mb" > "$ARB/build.log" 2>&1 \
    || { echo "der Kern laesst sich nicht bauen"; tail -5 "$ARB/build.log"; exit 1; }
echo "  Kern: $(stat -c%s "$ARB/k.mb") Oktette"

as --64 -o "$ARB/crt.o" kernel/user/crt.s 2>/dev/null
for p in $PROGS; do
    UPROF=""; UCRT="$ARB/crt.o"
    grep -qa '^profile app' "kernel/user/$p.fi" && { UPROF=--profile=app; UCRT=""; }
    "$FIRNC" $UPROF -c "kernel/user/$p.fi" -o "$ARB/$p.o" > "$ARB/$p.log" 2>&1 || {
        echo "  $p uebersetzt nicht:"; grep -E '^error' "$ARB/$p.log" | head -3; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$ARB/$p.elf" $UCRT "$ARB/$p.o" 2>/dev/null || {
        echo "  ld scheitert an $p"; exit 1; }
    strip --strip-all "$ARB/$p.elf"
done
echo "  Programme: $(echo $PROGS | wc -w)"

MK=()
for p in $PROGS; do MK+=("/bin/$p=$ARB/$p.elf"); done
python3 tools/osum/mkfs.py build "$ARB/disk.img" 8192 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ "${MK[@]}" /proc/ /dev/ /mnt/ /medien/ /etc/ \
    > "$ARB/mkfs.log" 2>&1 \
    || { echo "mkfs scheitert"; tail -3 "$ARB/mkfs.log"; exit 1; }
echo "  Platte: $(tail -1 "$ARB/mkfs.log")"

rm -f "$ARB/stick.img" "$ARB/stick.part"
dd if=/dev/zero of="$ARB/stick.img" bs=1M count=48 status=none
sfdisk "$ARB/stick.img" >/dev/null 2>&1 <<'SF'
label: dos
start=2048, type=c
SF
dd if=/dev/zero of="$ARB/stick.part" bs=1M count=46 status=none
mkfs.vfat -F32 -n OSUMSTICK "$ARB/stick.part" >/dev/null 2>&1
printf 'von linux auf den stick\n' > "$ARB/host.txt"
mcopy -i "$ARB/stick.part" "$ARB/host.txt" ::host.txt
dd if="$ARB/stick.part" of="$ARB/stick.img" bs=512 seek=2048 conv=notrunc status=none
rm -f "$ARB/stick.part"
echo "  Stick: FAT32, MBR, eine Datei des Wirts"

# ------------------------------------------------------------ der Lauf
#
# DIE SHELL IM FENSTER BEKOMMT IHR SKRIPT UEBER `script=` (`wmshell`).
# Getippt wird NICHT: eine Tastatur im Fenster ist eine eigene Zusage
# (Runde SYSTEMBUS, Abschnitt 9, hat sie ausdruecklich NICHT erbracht),
# und diese Runde misst den Wechseldatentraeger und nicht den Tastenweg.
# Das Skript haelt zwischen den Schritten an, damit jedes Bild einen
# fertigen Bildschirm zeigt.
SKRIPT='auswerfen;sleep 12;ls /medien/usb0;auswerfen;sleep 12;cat /medien/usb0/host.txt;auswerfen 0;auswerfen;sleep 8'

cat > "$ARB/dreh.txt" <<DREH
aufzeile wm: hold
warte 6
foto $ARB/10-vorher.ppm
stecke stk $ARB/stick.img
aufzeile wechsel: kommt
warte 10
foto $ARB/20-steckt.ppm
aufzeile wechsel: auswerfen
warte 8
foto $ARB/30-danach.ppm
warte 2
DREH

cp "$ARB/disk.img" "$ARB/live.img"
SOCK="$ARB/mon.sock"; rm -f "$SOCK"
APP="gfx wm wig wmshell wmhold wighalt=90 nokbd nosched noproc nofs usb vfs"
APP="$APP script=$SKRIPT"
( timeout 400 $QEMU_X86 -kernel "$ARB/k.mb" -m 512 -append "$APP" \
    -serial "file:$ARB/seriell.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$ARB/live.img,format=raw,if=ide,index=0" \
    -device qemu-xhci,id=xhci \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$ARB/qemu.log" 2>&1
  echo $? > "$ARB/rc" ) &
QP=$!
python3 tools/hotplug/monitor.py "$SOCK" "$ARB/seriell.txt" "$ARB/dreh.txt" \
    2>&1 | sed 's/^/  /'
i=0
while [ $i -lt 200 ]; do kill -0 "$QP" 2>/dev/null || break; sleep 0.5; i=$((i+1)); done
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo
echo "== was die Maschine gemeldet hat =="
grep -aE 'wechsel:|usb: msc|ausgeworfen|/medien/usb0|host.txt' "$ARB/seriell.txt" \
    | sed 's/^/  /' | head -14

echo
echo "== die Bilder =="
for n in 10-vorher 20-steckt 30-danach; do
    [ -s "$ARB/$n.ppm" ] || { echo "  $n: kein Bild"; continue; }
    python3 -c "
from PIL import Image
Image.open('$ARB/$n.ppm').save('$AUS/$n.png')
" 2>/dev/null && echo "  $AUS/$n.png ($(stat -c%s "$AUS/$n.png") Oktette)"
done
echo "  (Arbeitsverzeichnis: $ARB)"
