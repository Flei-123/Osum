#!/usr/bin/env bash
# Zeigt das Installationsfenster der Runde DUALBOOT.
#
# DIE KOMMANDOZEILE IST GEMESSEN UND NICHT GERATEN. Auf diesem Wirt
# laeuft der Fensterserver nur mit `desk wmshell` -- ohne die beiden
# bleibt die Leitung bei "init: dienste=1" stehen, und zwar auch mit der
# Abnahme der VORIGEN Runde (docs/RUNDE-DUALBOOT.md, Abschnitt 4.3).
# `wmhold`/`wighalt` allein genuegen hier nicht.
#
# Der Preis: `wmshell` legt den Starter ueber das Fenster. Deshalb wird
# er weggeklickt, bevor das Foto entsteht -- derselbe Weg, den ein
# Mensch nimmt.
cd /root/os-dual
. tools/lib/qemu.sh
O=/root/dualwork/fenster
rm -rf "$O"; mkdir -p "$O"

bash tools/dual/fremdplatte.sh "$O/platte.img" 80 > "$O/bau.txt" 2>&1
dd if=/dev/zero of="$O/leer.img" bs=1M count=0 seek=32 status=none

APPEND="modfs osum vfs gfx wm wig desk wmshell wmdauer herz tz=120 nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,${ARGS:-zeig}"

qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -m 512 \
  -kernel /root/dualwork/img/osum.mb -initrd /root/dualwork/img/root.img \
  -append "$APPEND" \
  -serial "file:$O/ser.txt" -display none -no-reboot \
  -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
  -drive "file=$O/leer.img,format=raw,if=ide,index=0" \
  -drive "file=$O/platte.img,format=raw,if=ide,index=1" \
  -monitor "unix:$O/mon,server,nowait" > "$O/qemu.log" 2>&1 &
QP=$!

mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$O/mon" >/dev/null 2>&1; }

for i in $(seq 1 60); do [ -S "$O/mon" ] && break; sleep 1; done
for i in $(seq 1 150); do
    grep -qa 'installer: ready\|installer: keine' "$O/ser.txt" 2>/dev/null && break
    sleep 1
done
sleep "${NACH:-8}"

# DEN STARTER WEGKLICKEN und das Fenster nach vorn holen.
mon 'mouse_move 400 60'
sleep 1
mon 'mouse_button 1'
sleep 1
mon 'mouse_button 0'
sleep 4

mon "screendump $O/fenster.ppm"
sleep 3
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

if [ -s "$O/fenster.ppm" ]; then
  python3 -c "
from PIL import Image
im = Image.open('$O/fenster.ppm')
im.save('$O/fenster.png')
im.crop((40, 40, 40 + 720, 40 + 560)).save('$O/nur-fenster.png')
g = im.convert('L'); w, h = g.size; px = g.load()
t = sum(1 for y in range(0, h, 3) for x in range(0, w, 3) if px[x, y] > 60)
print('Bild', im.size, 'Tinte', round(100 * t / ((h // 3) * (w // 3)), 1), '%')
"
  rm -f "$O/fenster.ppm"
fi
echo "== was der Installer gesagt hat =="
tr -d '\000' < "$O/ser.txt" | grep -a '^installer:' | head -30
echo "== im Fenster steht =="
tesseract "$O/nur-fenster.png" - 2>/dev/null | grep -v '^\s*$' | head -16
echo FERTIG
