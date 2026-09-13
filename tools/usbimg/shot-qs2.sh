#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbimg/shot-qs.sh -- EIN FOTO VOM KONTROLLZENTRUM (und vom Starter).
#
#   bash tools/usbimg/shot-qs.sh <bauverzeichnis> <ausgabe-praefix> [lang]
#
# macht <praefix>-qs.png       das Kontrollzentrum, offen
#       <praefix>-start.png    das Startmenue/der Starter, offen
#       <praefix>.txt          der serielle Mitschnitt dazu
#
# ==================================================================
# WARUM ES DIESES SKRIPT GIBT
# ==================================================================
#
# `tools/usbimg/run.sh` macht EIN Bild, und darauf steht der STARTER.
# Das ist richtig fuer das, was dort gemessen wird (deutsche Texte mit
# Umlauten), zeigt aber das KONTROLLZENTRUM nicht -- und das ist die
# Oberflaeche, an der Justin sich stoert. Ein Umbau, dessen Ergebnis
# man nicht sieht, ist eine Behauptung.
#
# ==================================================================
# WAS BEIM ERSTEN ANLAUF SCHIEFGING -- damit es niemand wiederholt
# ==================================================================
#
# 1. `wmhold` IST DAS ENDE UND NICHT DER BETRIEB.
#    Mit `wmhold` haelt der Fensterserver am Ende still, damit ein Foto
#    entstehen kann. Wer DANACH eine Taste schickt, dessen Druck steht
#    als letzte Zeile im Bericht und niemand liest ihn mehr:
#
#        wm: hold
#        wm: halt sek=20
#        hk: super+a        <- zu spaet, die Schleife der Leiste ist vorbei
#
#    Gebraucht wird der DAUERBETRIEB: `wmshell wmdauer herz`, genau wie
#    in tools/design/suchabnahme.sh. Dann laeuft die Schleife der
#    Leiste weiter, und `qs.step` liest den Hotkey-Zaehler wirklich.
#
# 2. DAS BILD KOMMT UEBER `screendump` AUS DEM MONITOR.
#    Kein zweites Werkzeug, kein eigener Weg -- dieselbe Zeile, die
#    suchabnahme.sh benutzt.
#
# 3. SUPER+A UND NICHT SUPER ALLEIN.
#    `Super` allein oeffnet das STARTMENUE (taskbar.fi), `Super+A` das
#    Kontrollzentrum (qs.fi: `nv.hotkey_key() == 97`). Der Kern LATCHT
#    beides mit einem Zaehler (kernel/kbd.fi), statt es an ein Fenster
#    zu geben -- ein Hotkey hat kein Fenster. Beide Leser nehmen sich
#    den Druck deshalb nicht gegenseitig weg.
set -uo pipefail
cd "$(dirname "$0")/../.."

IMGDIR=${1:?bauverzeichnis fehlt}
PREFIX=${2:?ausgabe-praefix fehlt}
LANG_=${3:-de}

[ -f "$IMGDIR/osum.mb" ] || { echo "== $IMGDIR/osum.mb fehlt" >&2; exit 1; }
[ -f "$IMGDIR/root.img" ] || { echo "== $IMGDIR/root.img fehlt" >&2; exit 1; }

W=$(mktemp -d)
trap 'kill $QP 2>/dev/null; rm -rf "$W"' EXIT

KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

# DER DAUERBETRIEB, nicht das Standbild -- siehe Punkt 1 im Kopf.
APPEND="modfs osum gfx wm wig desk wmshell wmdauer herz"
APPEND="$APPEND nosched noproc nofs lang=$LANG_ uiscale=2"

qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$IMGDIR/osum.mb" -initrd "$IMGDIR/root.img" \
    -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot -vga std \
    -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!

mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1; sleep "${2:-1}"; }
schuss() { mon "screendump $W/$1.ppm" 3; }

# Warten, bis die Leiste WIRKLICH laeuft -- nicht nur gestartet ist.
i=0
while [ $i -lt 400 ]; do
    grep -qa 'taskbar: state\|launcher: ready\|wm: windows' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i + 1))
done
sleep 8


# ---------------------------------------------------- das Kontrollzentrum
mon "sendkey esc" 2
mon "sendkey meta_l-a" 4
schuss 10-qs

# Wieder zu, damit das naechste Bild nicht beides zeigt.
mon "sendkey meta_l-a" 3

# ------------------------------------------------------------ der Starter

kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

mkdir -p "$(dirname "$PREFIX")"
cp "$W/serial.txt" "$PREFIX.txt" 2>/dev/null
for n in 00-schreibtisch 10-qs 20-start; do
    [ -s "$W/$n.ppm" ] || continue
    python3 -c "
from PIL import Image
Image.open('$W/$n.ppm').save('$PREFIX-${n#*-}.png')
" 2>/dev/null && echo "  $PREFIX-${n#*-}.png"
done

echo "  --- was die Oberflaeche gemeldet hat ---"
grep -aE '^(qs|hk|taskbar|launcher):' "$W/serial.txt" | head -25 | sed 's/^/      /'
