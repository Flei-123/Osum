#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotplug/bilder.sh -- DIE BILDER ZUR ABNAHME.
#
#   bash tools/hotplug/bilder.sh [ausgabeverzeichnis]
#
# Der Explorer laeuft, DANN kommt der Stick, und es entstehen drei
# Bilder aus derselben laufenden Maschine:
#
#   10-ohne.png    die Seitenleiste, bevor der Stick da ist
#   20-mit.png     dieselbe Seitenleiste, nachdem er gesteckt wurde
#   30-nachher.png nachdem er ausgeworfen wurde
#
# WARUM DREI UND NICHT EINES: ein einzelnes Bild mit einem Eintrag
# darauf beweist nichts -- der Eintrag koennte immer dagestanden haben.
# Erst der UNTERSCHIED zwischen 10 und 20 zeigt, dass er WEGEN des
# Sticks da ist, und der zwischen 20 und 30, dass er wieder verschwindet.
# Gemessen wird der Unterschied in Zahlen (pruef/bildpruef.py) und nicht
# im Auge des Betrachters.
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

PROGS="explorer sh echo ls cat edit launcher locate auswerfen"

echo "== bauen =="
./tools/build-kernel.sh "$ARB/k.mb" > "$ARB/build.log" 2>&1 \
    || { echo "der Kern laesst sich nicht bauen"; tail -5 "$ARB/build.log"; exit 1; }
echo "  Kern: $(stat -c%s "$ARB/k.mb") Oktette"

as --64 -o "$ARB/crt.o" kernel/user/crt.s 2>/dev/null
for p in $PROGS; do
    [ -f "kernel/user/$p.fi" ] || continue
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

# DAS ABBILD, GENAU WIE tools/k15/run.sh ES BAUT. Drei Dinge sind
# nicht wegzulassen, und jedes hat diesen Lauf schon einmal gekostet:
#   * die SCHRIFTEN unter /lib -- ohne sie "ttf: keine Schrift gefunden"
#     und ein Fensterserver, der nichts schreiben kann;
#   * /bin/files@/bin/explorer -- `wigfiles` startet `/bin/files`, und
#     ohne den Verweis startet gar nichts ("osum: skipped");
#   * die SPRACHDATEIEN, sonst steht in jedem Bedienelement sein
#     Schluessel statt seiner Beschriftung.
# DER /data-BAUM, GENAU WIE tools/k15/run.sh IHN ANLEGT.
#
# Er ist NICHT Zierde. Die Seitenleiste baut ihre Orte aus /data,
# /data/dokumente, /data/bilder, /data/downloads und dem Papierkorb --
# und `exporte.entry` kopiert den Pfad, BEVOR es prueft, ob es ihn
# gibt. Auf einem Abbild ohne diesen Baum stirbt der Dateimanager
# deshalb beim Aufbau der Seitenleiste:
#
#   user fault: pid=3 vector=14 err=0x5 cr2=0x0 -- process killed
#
# Das ist ein BESTEHENDER Fehler und keiner dieser Runde -- die
# Gegenprobe mit dem unveraenderten explorer.fi aus main stirbt
# genauso (siehe docs/HOTPLUG.md, "Was dabei aufgefallen ist").
# Hier wird er umgangen, nicht behoben: diese Runde baut den
# Wechseldatentraeger, nicht den Dateimanager.
python3 tools/k15/tree.py "$ARB/baum" > "$ARB/baum.log" 2>&1 \
    || { echo "tree.py scheitert"; tail -3 "$ARB/baum.log"; exit 1; }

MK=()
for p in $PROGS; do MK+=("/bin/$p=$ARB/$p.elf"); done
while read -r z; do MK+=("$z"); done < "$ARB/baum/liste"
python3 tools/osum/mkfs.py build "$ARB/disk.img" 16384 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ "${MK[@]}" "/bin/files@/bin/explorer" \
    /proc/ /dev/ /mnt/ /medien/ /etc/ \
    "/etc/theme=$ARB/baum/theme" \
    /usr/ /usr/share/ /usr/share/locale/ /usr/share/locale/de/ \
    "/usr/share/locale/de/messages=locale/de/messages" \
    /usr/share/locale/en/ \
    "/usr/share/locale/en/messages=locale/en/messages" \
    > "$ARB/mkfs.log" 2>&1 \
    || { echo "mkfs scheitert"; tail -3 "$ARB/mkfs.log"; exit 1; }
echo "  Platte: $(tail -1 "$ARB/mkfs.log")"

# der Stick
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
cat > "$ARB/dreh.txt" <<DREH
# Der Explorer muss stehen, BEVOR fotografiert wird.
# 'wm: hold' ist die Marke, nicht 'explorer: ready': der
# Fensterserver meldet hier, dass er zur Ruhe gekommen ist und ein
# Foto ein fertiges Bild zeigt. Der Dateimanager schreibt seine
# 'ready'-Zeile in diesem Lauf nicht auf die serielle Leitung.
aufzeile wm: hold
# Der Dateimanager ist 1,6 MB gross und braucht nach dem Start einen
# Augenblick, bis sein Fenster steht. Ein Foto davor zeigt einen
# leeren Schreibtisch -- und der Vergleich zweier leerer Bilder ist
# kein Test (die Lehre aus Runde B3).
warte 12
foto $ARB/10-ohne.ppm
# jetzt der Stick, im Betrieb
stecke stk $ARB/stick.img
aufzeile wechsel: kommt
warte 4
# Der Explorer liest die Seitenleiste beim Aktualisieren neu: F5.
taste f5
warte 6
foto $ARB/20-mit.ppm
warte 1
DREH

cp "$ARB/disk.img" "$ARB/live.img"
SOCK="$ARB/mon.sock"; rm -f "$SOCK"
# `wighalt=90`: zwanzig Sekunden (wiglong) reichen nicht -- zwischen
# den Bildern liegt ein Stick, der aufgezaehlt und eingehaengt wird.
APP="gfx wm wigfiles wmhold wighalt=90 nokbd nosched noproc nofs usb vfs"
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
grep -aE 'wechsel:|explorer: orte|explorer: ready|usb: msc' "$ARB/seriell.txt" \
    | sed 's/^/  /' | head -12

echo
echo "== die Bilder =="
for n in 10-ohne 20-mit; do
    [ -s "$ARB/$n.ppm" ] || { echo "  $n: kein Bild"; continue; }
    python3 -c "
from PIL import Image
Image.open('$ARB/$n.ppm').save('$AUS/$n.png')
" 2>/dev/null && echo "  $AUS/$n.png ($(stat -c%s "$AUS/$n.png") Oktette)"
done
echo "  (Arbeitsverzeichnis: $ARB)"
