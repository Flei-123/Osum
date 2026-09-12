#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge2/stickstart.sh -- RUNDE MERGE-11: WAS JUSTIN WIRKLICH TUT.
#
# Der Unterschied zu tools/bridge2/https443.sh ist genau EIN Wort, und
# es ist das entscheidende: dieser Laeufer startet `jarvisd` NICHT
# selbst ueber `script=`. Er faehrt die BEFEHLSZEILE DES STICKS und
# schaut zu, ob der Kern den Helfer von sich aus hochbringt.
#
# WARUM DAS EIN EIGENER LAEUFER IST. https443.sh hat bewiesen, dass
# jarvisd ueber 443 mit store.fleitec.com sprechen KANN -- aber es hat
# ihn von Hand gestartet. Im Abbild lag das Programm da und niemand
# rief es. Justin haette gebootet, gewartet und nie einen Code gesehen.
# Genau diese Luecke misst dieser Laeufer.
#
# Er beweist die Kette, die Justin erlebt:
#   Stick booten -> Schreibtisch -> dhcp -> jarvisd -> Code am Schirm
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
W=${STICK_W:-/tmp/bruecke-stick}
BUILDD=${DESIGNBUILD:-/tmp/osum-eh5build-e9e5f1ff94da}
rm -rf "$W"; mkdir -p "$W"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null || { echo "kein qemu"; exit 0; }
[ -s "$BUILDD/k0.mb" ] || { echo "kein Kern in $BUILDD"; exit 1; }

# Der Kern MUSS der frische sein -- der mit dem Autostart.
./tools/build-kernel.sh "$W/k0.mb" > "$W/k.log" 2>&1 || {
    echo "der Kern baut nicht"; tail -20 "$W/k.log"; exit 1; }
note "kernel $(stat -c%s "$W/k0.mb") Oktette"

# Die Platte des eh5-Laeufers wiederverwenden: sie hat die 55
# Programme, /bin/jarvisd und /bin/dhcp.
# Die WURZEL DES ECHTEN ABBILDES -- dort liegt /bin/jarvisd.
[ -s "${STICK_ROOT:-/tmp/m11-img2/root.img}" ] && cp "${STICK_ROOT:-/tmp/m11-img2/root.img}" "$W/disk.img"
[ -s "$W/disk.img" ] || { echo "keine Platte -- erst tools/design/eh5.sh laufen lassen"; exit 1; }

# DIE BEFEHLSZEILE DES STICKS, woertlich aus tools/usbimg/build.sh,
# minus `modfs` (die Platte kommt hier ueber -drive).
APPEND="osum gfx fbres=1280x800 wm wig desk wmshell wmdauer tafel herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=en"
APPEND="$APPEND nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis"
APPEND="$APPEND nosched noproc nofs"
note "append $APPEND"

timeout 240 qemu-system-x86_64 -kernel "$W/k0.mb" -m 512 \
    -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=1280,yres=800,vgamem_mb=32" \
    -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    > "$W/qemu.log" 2>&1 &
QPID=$!
i=0
while [ $i -lt 700 ]; do
    grep -qa 'KOPPLUNGSCODE\|jarvisd: angemeldet' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.2; i=$((i+1))
done
sleep 5
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null

echo "== was auf der Leitung stand =="
grep -aE 'dhcp:|jarvisd:|desk: start' "$W/serial.txt" | head -20 | sed 's/^/        /'

grep -qa 'desk: start /bin/jarvisd\|jarvisd: bereit' "$W/serial.txt" \
    && ok "der Kern startet /bin/jarvisd VON SELBST" \
    || bad "jarvisd wird nicht gestartet"
grep -qa 'resolv.conf geschrieben' "$W/serial.txt" \
    && ok "dhcp hat /etc/resolv.conf geschrieben" \
    || bad "kein resolv.conf -- dann gibt es keine Namensaufloesung"
grep -qa 'jarvisd: der Name laesst sich nicht aufloesen' "$W/serial.txt" \
    && bad "der Name loest nicht auf" \
    || ok "store.fleitec.com loest auf"
grep -qa 'KOPPLUNGSCODE' "$W/serial.txt" \
    && ok "das Geraet zeigt einen KOPPLUNGSCODE" \
    || bad "kein Kopplungscode"

HEX=$(grep -a 'KOPPLUNGSCODE' "$W/serial.txt" | tail -1 | awk '{print $NF}')
if [ -n "$HEX" ]; then
    note "Code, den Justin vorliest: $(python3 -c "import sys;print(bytes.fromhex(sys.argv[1]).decode())" "$HEX" 2>/dev/null)"
fi

echo "== und was der Dienst dazu sagt =="
journalctl -u bruecke --since '-4 min' --no-pager 2>/dev/null \
    | grep -iE 'KOPPLUNG NOETIG|ANGEMELDET' | tail -3 | sed 's/^/        /'
journalctl -u bruecke --since '-4 min' --no-pager 2>/dev/null \
    | grep -qi 'KOPPLUNG NOETIG' \
    && ok "der Dienst hat den Code ausgestellt" \
    || bad "im Protokoll des Dienstes steht nichts"

echo
echo "STICKSTART: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
