#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# pruef/start.sh -- EINE Maschine starten, Monitor auf einem Unix-Socket.
#   bash start.sh <name> <breite> <hoehe> [zusatz-cmdline]
#
# Woertlich der Weg aus /root/osum-durchklick/start.sh, damit die Zahlen
# der Runde DURCHKLICK und die dieser Runde vergleichbar sind. Der
# einzige Unterschied: Kern und Wurzel kommen aus DIESEM Arbeitsbaum
# (pruef/osum.mb + pruef/root.img, aus tools/usbimg/build.sh).
set -uo pipefail
cd "$(dirname "$0")"

NAME=${1:-lauf}
BREITE=${2:-1280}
HOEHE=${3:-800}
EXTRA=${4:-}

D=$(pwd)/laeufe/$NAME
rm -rf "$D"; mkdir -p "$D"

# Die Kommandozeile des Schreibtisch-Eintrags aus limine.conf, woertlich.
CMD="modfs osum gfx ${FBMODE:-} wm wig desk wmshell wmdauer tafel herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp ${PROCMODE:-nosched noproc nofs} fbres=${BREITE}x${HOEHE} $EXTRA"

KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

echo "$CMD" > "$D/cmdline.txt"
date +%s.%N > "$D/start.zeit"

timeout "${FRIST:-900}" qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
    -kernel osum.mb -initrd root.img -append "$CMD" \
    -vga std \
    -device usb-ehci,id=ehci -device usb-tablet -device usb-kbd \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -serial "file:$D/serial.txt" \
    -monitor "unix:$D/mon.sock,server,nowait" \
    -display none -no-reboot \
    > "$D/qemu.txt" 2>&1 &
echo $! > "$D/pid"
echo "gestartet: $NAME (pid $(cat "$D/pid")) ${BREITE}x${HOEHE} -> $D"
