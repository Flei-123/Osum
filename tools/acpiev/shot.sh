#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/acpiev/shot.sh -- DIE BILDER DER RUNDE.
#
#   bash tools/acpiev/shot.sh <bauverz> <ausgabe.png> <was> [sekunden]
#
# `was` ist einer von:
#   leiste   der Schreibtisch mit dem Akku in der Leiste (77 %)
#   deckel   Deckel zuklappen -> der Sperrbildschirm muss kommen
#   taste    die Einschalttaste druecken -> das Energiemenue
#
# Der Weg ist der aus `tools/anmeldung/shot.sh`; hier steht nur, WAS
# ausgeloest wird und WANN das Bild entsteht.
#
# QEMU 7.2 hat weder Deckel noch Akku. `tools/acpiev/asl/laptop.aml`
# baut beide nach und wird mit `-acpitable` eingehaengt; ausgeloest
# wird mit den Woertern `evfake`/`evlid`, weil es an dieser Maschine
# keine Hardware gibt, die das GPE-Bit zieht. Die EINSCHALTTASTE ist
# davon ausgenommen: die kann QEMU wirklich, ueber `system_powerdown`
# am Monitor, und genau so wird sie hier gedrueckt.
set -uo pipefail
cd "$(dirname "$0")/../.."

BUILD=${1:?bauverzeichnis fehlt}
OUT=${2:?ausgabe.png fehlt}
WAS=${3:?was fehlt (leiste|deckel|taste)}
SEK=${4:-45}

[ -f "$BUILD/osum.mb" ] || { echo "== $BUILD/osum.mb fehlt" >&2; exit 1; }

TAB=tools/acpiev/asl/laptop.aml
if [ ! -f "$TAB" ]; then
    command -v iasl >/dev/null 2>&1 || {
        echo "== iasl fehlt und $TAB ist nicht gebaut" >&2; exit 1; }
    ( cd tools/acpiev/asl && iasl laptop.asl >/dev/null 2>&1 )
fi

W=$(mktemp -d)
QP=""
trap 'kill $QP 2>/dev/null; rm -rf "$W"' EXIT
cp "$BUILD/root.img" "$W/disk.img"

KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

EXTRA="acpiev evfake"
[ "$WAS" = "deckel" ] && EXTRA="acpiev evfake evlid"

APPEND="gfx fbres=1280x800 wm wig desk wmshell wmdauer herz"
APPEND="$APPEND nosched noproc nofs lang=de uiscale=1 $EXTRA"

timeout $((SEK + 40)) qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$BUILD/osum.mb" -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -acpitable "file=$TAB" \
    -monitor "unix:$W/mon,server,nowait" \
    -drive "file=$W/disk.img,format=raw,if=ide,index=0" &
QP=$!

mon() {
    printf '%s\n' "$1" | timeout 10 socat - "unix-connect:$W/mon" >/dev/null 2>&1
}
wandeln() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PY
}

# Warten, bis der Schreibtisch steht.
for _ in $(seq 1 400); do
    grep -qa 'acpiev: ready=' "$W/serial.txt" 2>/dev/null && break
    kill -0 $QP 2>/dev/null || break
    sleep 0.1
done
sleep 16

# DAS BILD VORHER -- ohne das ist "danach sieht es anders aus" keine
# Messung, sondern eine Behauptung.
mon "screendump $W/vor.ppm"; sleep 1
[ -f "$W/vor.ppm" ] && wandeln "$W/vor.ppm" "${OUT%.png}-vorher.png"

case "$WAS" in
    leiste)
        : # nichts ausloesen, das Bild ist der Zustand
        ;;
    deckel)
        # Der Kern klappt den Deckel selbst zu (Wort `evlid`), weil
        # QEMU kein Deckelgeraet hat. Gewartet wird auf die Zeile.
        for _ in $(seq 1 200); do
            grep -qa 'deckel zu' "$W/serial.txt" 2>/dev/null && break
            sleep 0.1
        done
        sleep 4
        ;;
    taste)
        # DIE ECHTE TASTE. `system_powerdown` setzt PWRBTN_STS und
        # zieht den SCI -- das ist kein Nachbau.
        mon "system_powerdown"
        sleep 6
        ;;
esac

sleep 2
mon "screendump $W/ende.ppm"; sleep 2
[ -f "$W/ende.ppm" ] && wandeln "$W/ende.ppm" "$OUT"
cp "$W/serial.txt" "${OUT%.png}.txt" 2>/dev/null

kill $QP 2>/dev/null
wait $QP 2>/dev/null
echo "== Bild:    $OUT"
echo "== Vorher:  ${OUT%.png}-vorher.png"
echo "== Bericht: ${OUT%.png}.txt"
