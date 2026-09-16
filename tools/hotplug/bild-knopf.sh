#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotplug/bild-knopf.sh -- DER AUSWURFKNOPF, IM BILD UND GEDRUECKT.
#
#   bash tools/hotplug/bild-knopf.sh [ausgabeverzeichnis]
#
# Die Vorrunde konnte den Knopf nicht fotografieren ("der Dateimanager
# startet in diesem Baum nicht bis zum Fenster"). Das lag NICHT am
# Dateimanager, sondern am Abbild: ohne den /data-Baum stirbt er beim
# Aufbau der Seitenleiste. Mit `tools/k15/tree.py` laeuft er, und damit
# ist der Weg frei fuer das, was die Vorrunde offenliess.
#
# DREI DINGE, DIE HIER ANDERS SIND ALS IN `bilder.sh`:
#
#   * /etc/uitrace LIEGT AUF DER PLATTE. Ohne die Datei meldet kein
#     Programm seine Bedienelemente (`dbg_setup`), und dann klickt man
#     auf geratene Koordinaten. Mit ihr steht jedes Rechteck im
#     Mitschnitt, und `knopf.py` rechnet den Klickpunkt aus.
#   * EINE MAUS IST ANGESTECKT (`-device usb-mouse`). In `bilder.sh`
#     hing keine -- ein Klick war dort gar nicht moeglich.
#   * KEIN F5. Der Dateimanager haengt seit dieser Runde am Systembus
#     und liest die Orte neu, sobald der Kern das Kommen meldet. Genau
#     das ist die Zusage, die das zweite Bild zeigt.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}

AUS=${1:-docs/shots/hotplug2}
mkdir -p "$AUS"
ARB=${HP_ARB:-$(mktemp -d)}
mkdir -p "$ARB"
[ -n "${HP_ARB:-}" ] || trap 'rm -rf "$ARB"' EXIT

PROGS="explorer sh echo ls cat edit launcher locate auswerfen"

for w in mkfs.vfat mcopy sfdisk qemu-system-x86_64 python3; do
    command -v "$w" >/dev/null 2>&1 || { echo "KNOPF: uebersprungen, $w fehlt"; exit 0; }
done
python3 -c "import PIL" 2>/dev/null || { echo "KNOPF: uebersprungen, PIL fehlt"; exit 0; }

echo "== bauen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || {
    [ -x "$FIRNC" ] || { echo "kein firnc"; exit 1; }; }
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

python3 tools/k15/tree.py "$ARB/baum" > "$ARB/baum.log" 2>&1 \
    || { echo "tree.py scheitert"; tail -3 "$ARB/baum.log"; exit 1; }

# OHNE DIESE DATEI SCHWEIGT DIE OBERFLAECHE. Siehe `dbg_setup` in
# explorer.fi: erst mit ihr meldet jedes Bedienelement sein Rechteck.
printf 'on\n' > "$ARB/uitrace"

MK=()
for p in $PROGS; do MK+=("/bin/$p=$ARB/$p.elf"); done
while read -r z; do MK+=("$z"); done < "$ARB/baum/liste"
python3 tools/osum/mkfs.py build "$ARB/disk.img" 16384 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ "${MK[@]}" "/bin/files@/bin/explorer" \
    /proc/ /dev/ /mnt/ /medien/ /etc/ \
    "/etc/theme=$ARB/baum/theme" "/etc/uitrace=$ARB/uitrace" \
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

cp "$ARB/disk.img" "$ARB/live-knopf.img"

echo
echo "== der Lauf =="
python3 tools/hotplug/knopf.py "$ARB" "$AUS"
RC=$?

echo
echo "== was die Maschine gemeldet hat =="
grep -aE 'wechsel:|explorer: orte |explorer: auswerfen|explorer: ausknopf' \
    "$ARB/knopf-seriell.txt" 2>/dev/null | sed 's/^/  /' | head -14
echo "  (Arbeitsverzeichnis: $ARB)"
exit $RC
