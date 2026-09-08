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
# RUNDE TUERSCHLOSS: `dhcp` ist STANDARDMAESSIG AUS, und das ist eine
# Messentscheidung, keine Bequemlichkeit.
#
# Der DHCP-Dienst schreibt auf DIESELBE serielle Leitung wie der Starter
# und mitten in dessen Zeilen hinein. Gemessen:
#
#   launcher: treffer i=0 name=[Datei-Explorer] exec=[/appserver 10.0.2.3
#
# Der Pfad ist damit unlesbar, und wer daraus "die App fehlt" schliesst,
# misst das Gedraenge auf der Leitung und nicht das System. Fuer den
# Netz-Pruefpunkt wird DHCP eigens eingeschaltet (MITNETZ=1) -- dann
# steht die Uhrzeit der Messung fest und nicht das Gedraenge.
NETZ=""
[ "${MITNETZ:-0}" = "1" ] && NETZ="dhcp"
# RUNDE TUERSCHLOSS: `tafel` IST STANDARDMAESSIG AUS.
#
# Die Messtafel malt 24 Zeilen Diagnose in GRUEN ueber den ganzen
# Schirm -- ueber den Schreibtisch, ueber die Fenster, ueber das
# Terminal. Gemessen: gruene Tinte von x=4 bis x=749 und y=72 bis
# y=759, waehrend das Terminalfenster bei (24,40) nur 560x380 gross
# ist. Wer den Inhalt des Terminals im Bild lesen will, liest die
# Tafel und nicht die Shell -- und haelt eine Shell, die sauber
# antwortet, fuer stumm. Genau das ist in dieser Runde passiert.
#
# Fuer die Tafel selbst gibt es MITTAFEL=1.
TAFEL=""
[ "${MITTAFEL:-0}" = "1" ] && TAFEL="tafel"
CMD="modfs osum gfx ${FBMODE:-} wm wig desk wmshell wmdauer $TAFEL herz absturzhalt nopuls tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 $NETZ ${PROCMODE:-nosched noproc nofs} fbres=${BREITE}x${HOEHE} $EXTRA"

# ===================================================== RUNDE TUERSCHLOSS
#
# xHCI UND NICHT EHCI -- DER GRUND, WARUM IN DIESEM AUFBAU NIE EINE
# TASTE ANKAM.
#
# Hier stand `-device usb-ehci`, woertlich uebernommen aus
# /root/osum-durchklick/start.sh. Der USB-Teil dieses Kerns hat aber
# genau EINEN Wirtstreiber, und das ist xHCI (kernel/usb.fi:
# `if !xhci.present(state) { serial: "usb: no controller"; return }`).
# Gemessen im ersten Lauf dieser Runde:
#
#     pci: 00:03.0 8086:24cd class=0c:03:20 usb
#     usb: no controller
#
# Damit wurde nie ein Geraet aufgezaehlt, nie eine Tastatur gefunden,
# und auf der ganzen seriellen Leitung steht keine einzige `key:`-Zeile.
# Jede Aussage der Vorrunde ueber TASTEN -- Super+A (2.5), Alt+Tab
# (4.3), Tippen (3.7), AltGr (6.3) -- hat deshalb nicht das System
# gemessen, sondern diesen Schalter. Die Maus ging, weil sie ueber PS/2
# laeuft (`-vga std` + Monitor `mouse_move`), und der Unterschied
# zwischen "Maus geht, Tastatur nicht" haette schon damals auffallen
# muessen.
#
# `qemu-xhci` ist dasselbe Geraet, mit dem tools/hid/run.sh seit Runde
# HID misst -- dort kommen Tastatur und Maus vollstaendig an.
KVM=()
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

echo "$CMD" > "$D/cmdline.txt"
date +%s.%N > "$D/start.zeit"

timeout "${FRIST:-2400}" qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
    -kernel osum.mb -initrd root.img -append "$CMD" \
    -vga std \
    -device qemu-xhci,id=xhci -device usb-tablet -device usb-kbd \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -serial "file:$D/serial.txt" \
    -monitor "unix:$D/mon.sock,server,nowait" \
    -display none -no-reboot \
    > "$D/qemu.txt" 2>&1 &
echo $! > "$D/pid"
echo "gestartet: $NAME (pid $(cat "$D/pid")) ${BREITE}x${HOEHE} -> $D"
