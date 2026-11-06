#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/acceptance3440.sh [kern.mb] [wurzel.img] [ausgabe]
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/r3-k.mb}
WURZEL=${2:-/tmp/final-img/root.img}
W=${3:-/tmp/abnahme3440}
rm -rf "$W"; mkdir -p "$W"
[ -s "$KERN" ] || { echo "kein Kern: $KERN"; exit 1; }
[ -s "$WURZEL" ] || { echo "no root: $WURZEL"; exit 1; }
cp "$WURZEL" "$W/disk.img"

pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

APPEND="osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer tafel herz"
APPEND="$APPEND crashhalt nopuls tz=120 lang=en usb hidgen modfs"
APPEND="$APPEND nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis"
APPEND="$APPEND nosched noproc nofs"
echo "append: $APPEND"
echo

qemu-system-x86_64 -kernel "$KERN" -m 2048 -append "$APPEND" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -netdev user,id=n0 -device e1000,netdev=n0 \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 700 ]; do
    grep -qa 'PAIRING CODE' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.3; i=$((i+1))
done
sleep 8
printf 'screendump %s/schirm.ppm\n' "$W" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1
sleep 4
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo "== Bildspeicher =="
grep -a '^fb: 3440' "$W/serial.txt" | sed 's/^/   /'
echo "== Start =="
grep -a 'desk: start' "$W/serial.txt" | sed 's/^/   /'
echo "== jarvisd =="
grep -a 'jarvisd:' "$W/serial.txt" | head -6 | sed 's/^/   /'
echo

n=$(grep -acE "CRASH|EXCEPTION" "$W/serial.txt" 2>/dev/null | head -1); n=${n:-0}
[ "$n" -eq 0 ] && ok "no crash at 3440x1440" || bad "$n Absturzzeilen"
grep -qa 'huge=10' "$W/serial.txt" \
    && ok "all ten tiles rendered (no strip mode)" \
    || bad "the framebuffer is not hanging on one piece"
for p in desktop taskbar launcher; do
    grep -qa "desk: start /bin/$p" "$W/serial.txt" \
        && ok "$p laeuft" || bad "$p laeuft NICHT"
done
grep -qa 'desk: start /bin/jarvisd' "$W/serial.txt" \
    && ok "jarvisd starts BY ITSELF" || bad "jarvisd startet nicht"
HEX=$(grep -a 'PAIRING CODE' "$W/serial.txt" | tail -1 | awk '{print $NF}')
if [ -n "$HEX" ]; then
    CODE=$(python3 -c "import sys;print(bytes.fromhex(sys.argv[1]).decode())" "$HEX" 2>/dev/null)
    if [ "${#CODE}" -eq 6 ]; then
        ok "six-digit pairing code on screen: $CODE"
    else
        bad "code has ${#CODE} digits: $CODE"
    fi
else
    bad "kein Kopplungscode"
fi
[ -s "$W/schirm.ppm" ] && ok "Bildschirmabzug abgelegt ($W/schirm.ppm)" \
    || bad "kein Abzug"

echo
echo "ABNAHME 3440x1440: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
