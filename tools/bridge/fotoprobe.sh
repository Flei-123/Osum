#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge/fotoprobe.sh -- RUNDE BRIDGE-2: WAS SIEHT RING 3 VOM SCHIRM?
#
# Ein kleiner Laeufer nur fuer die eine Frage, an der Abschnitt 12 der
# Abnahme haengt: gibt der Kern dem Helfer ein Bildschirmfoto, und wenn
# nein, WORAN GENAU liegt es. Er startet Osum mit `gfx` und laesst
# `jarvisd -s` die Zahlen auf die serielle Leitung schreiben.
#
#   bash tools/bridge/fotoprobe.sh [weitere Kernwoerter]
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${FOTOPROBE_W:-/tmp/fotoprobe}
mkdir -p "$W"

if [ ! -f "$W/k.mb" ] || [ -n "${FOTOPROBE_BAU:-}" ]; then
    bash tools/bridge/build.sh "$W" 0 || exit 1
fi
K="$W/k.mb"

cat > "$W/rechte.conf" <<'CONF'
server         = 10.9.0.1:8443
servername     = jarvis.test
roots        = /etc/ssl/roots.pem
commands        = no
read          = /var/jarvis/
write      = /var/jarvis/
list      = /var/jarvis/
screenshot = yes
sysinfo     = yes
max_output    = 65536
max_file      = 4194304
log       = /var/log/jarvisd.log
work_file    = /var/jarvis/output.txt
permit_file = /var/jarvis/screenshot-permit
CONF
: > "$W/leer.pem"

SPEC="/bin/ /etc/ /etc/ssl/ /etc/jarvis/ /var/ /var/log/ /var/jarvis/"
for p in sh ls cat echo chmod jsig jarvisctl; do
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done
SPEC="$SPEC /bin/jarvisd=$W/jarvisd.elf"
SPEC="$SPEC /etc/jarvis/permissions.conf=$W/rechte.conf /etc/ssl/roots.pem=$W/leer.pem"
python3 tools/osum/mkfs.py build "$W/probe.img" 16384 $SPEC > "$W/mkfs.txt" 2>&1 || {
    echo "mkfs gescheitert"; tail -5 "$W/mkfs.txt"; exit 1; }

SKRIPT=${FOTOPROBE_SKRIPT:-"jarvisd -s;jarvisctl screenshot 600;jarvisd -f /var/jarvis/schuss.png;ls /var/jarvis;exit"}
cp "$W/probe.img" "$W/live.img"
timeout 180 qemu-system-x86_64 -kernel "$K" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 gfx $* script=$SKRIPT" \
    -serial "file:$W/seriell.txt" -display none -no-reboot \
    -drive "file=$W/live.img,format=raw,if=ide,index=0" \
    -vga std \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1

echo "---- die Zeilen, auf die es ankommt ----"
grep -aE 'schirm:|shot:|fb:|jarvisd:|foto|schuss' "$W/seriell.txt" | head -40
echo "---- (voll in $W/seriell.txt) ----"
