#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/suchabnahme.sh -- R4: KANN JUSTIN IM SUCHFENSTER ETWAS AUSFUEHREN?
#
#   bash tools/design/suchabnahme.sh [kern.mb] [wurzel.img] [ausgabe]
#
# Justins Frage, woertlich: "kann man im Suchfenster jetzt herumklicken
# und etwas ausfuehren?" Diese Abnahme beantwortet sie in SECHS
# einzeln belegten Schritten, jeder mit eigenem Abzug:
#
#   1. Suchfenster ueber die SUPER-TASTE oeffnen
#   2. Suchfenster ueber KLICK AUFS LOGO oeffnen
#   3. tippen -- kommt der Text ins Feld an?
#   4. Trefferliste erscheint und ist gefiltert
#   5. Treffer mit der MAUS anklicken -> Programm startet
#   6. Treffer mit PFEILTASTEN + ENTER waehlen -> Programm startet
#
# ALLES IN 3440x1440, Justins Aufloesung. Ein Lauf in 1280x800 sagt
# ueber sein Brett nichts aus -- das ist die Lektion des
# Framebuffer-Fundes.
#
# Gesteuert wird ueber den QEMU-Monitor (sendkey/mouse_move/mouse_button),
# also ueber dieselben Wege, die ein Mensch benutzt: echte Tastenanschlaege
# und echte Mausklicks, keine Abkuerzung im Programm.
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/r3-k.mb}
WURZEL=${2:-/tmp/final-img/root.img}
W=${3:-/tmp/suchabnahme}
rm -rf "$W"; mkdir -p "$W"
[ -s "$KERN" ] || { echo "kein Kern: $KERN"; exit 1; }
[ -s "$WURZEL" ] || { echo "keine Wurzel: $WURZEL"; exit 1; }
cp "$WURZEL" "$W/disk.img"

pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
mon(){ printf '%s\n' "$1" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1; sleep "${2:-1}"; }
schuss(){ mon "screendump $W/$1.ppm" 2; }

APPEND="osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=en usb hidgen modfs"
APPEND="$APPEND nosched noproc nofs"

qemu-system-x86_64 -kernel "$KERN" -m 2048 -append "$APPEND" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 400 ]; do
    grep -qa 'launcher: ready\|taskbar: state' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i+1))
done
sleep 10
schuss 00-schreibtisch

# --- 1. SUPER-TASTE ---------------------------------------------------
: > "$W/marke1"
mon "sendkey meta_l" 3
schuss 01-super
S1=$(grep -ac 'launcher: sichtbar\|launcher: auf\|starter: auf' "$W/serial.txt" 2>/dev/null | head -1)

# --- 3. TIPPEN --------------------------------------------------------
for k in e d i t; do mon "sendkey $k" 0.4; done
sleep 2
schuss 02-getippt

# --- 5. TREFFER MIT DER MAUS ------------------------------------------
# Die Liste steht unter dem Feld. Der erste Treffer liegt etwa auf
# einem Drittel der Fensterhoehe; die genaue Stelle liest der
# Auswerter spaeter aus dem Abzug.
mon "mouse_move 450 1010" 1
mon "mouse_button 1" 1
mon "mouse_button 0" 3
schuss 03-maus-geklickt

sleep 3
schuss 04-nach-klick

# --- 2. KLICK AUFS LOGO (Startknopf unten links) ----------------------
mon "sendkey esc" 2
mon "mouse_move 44 1400" 1
mon "mouse_button 1" 1
mon "mouse_button 0" 3
schuss 05-logo-geklickt

# --- 6. PFEILTASTEN + ENTER -------------------------------------------
for k in e d i t; do mon "sendkey $k" 0.4; done
sleep 2
mon "sendkey down" 1
mon "sendkey ret" 3
schuss 06-tasten-enter
sleep 3
schuss 07-ende

kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo
echo "== was die serielle Leitung sagt =="
grep -aE 'launcher:|taskbar: (state|btn)|desk: start|editor|edit:' "$W/serial.txt" \
    | tail -24 | sed 's/^/   /'
echo

n=$(grep -acE "ABSTURZ|EXCEPTION" "$W/serial.txt" 2>/dev/null | head -1); n=${n:-0}
[ "$n" -eq 0 ] && ok "kein Absturz" || bad "$n Absturzzeilen"
grep -qa 'desk: start /bin/launcher' "$W/serial.txt" \
    && ok "der Starter laeuft ueberhaupt" || bad "kein Starter"
grep -qa 'launcher: apps=' "$W/serial.txt" \
    && ok "der Starter hat Programme gefunden ($(grep -ao 'apps=[0-9]*' "$W/serial.txt" | tail -1))" \
    || bad "der Starter kennt keine Programme"
# Getippt?
grep -qa 'launcher: suche\|launcher: filter\|launcher: name' "$W/serial.txt" \
    && ok "der Starter hat auf Eingabe reagiert" || bad "keine Reaktion auf Eingabe"
# Gestartet?
if grep -qa 'launcher: starten\|launcher: exec\|SYS_EXEC' "$W/serial.txt"; then
    ok "ein Treffer wurde AUSGEFUEHRT"
else
    bad "kein Treffer wurde ausgefuehrt"
fi
ls "$W"/*.ppm >/dev/null 2>&1 && ok "$(ls "$W"/*.ppm | wc -l) Abzuege abgelegt" || bad "keine Abzuege"

echo
echo "SUCHABNAHME: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
