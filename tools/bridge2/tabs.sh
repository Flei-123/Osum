#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OUT=${REITER_OUT:-/tmp/bruecke-reiter}
mkdir -p "$OUT"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "REITER: uebersprungen, qemu fehlt"; exit 0; }

SOCK="$OUT/mon.sock"
QPID=""
cleanup() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; rm -f "$SOCK"; }
trap cleanup EXIT

echo "== 1. das Abbild =="
if [ ! -f "$OUT/disk.img" ]; then
    bash tools/look/shot.sh "$OUT" keep=yes >"$OUT/bau.log" 2>&1 || {
        echo "the build failed"; tail -6 "$OUT/bau.log"; exit 1; }
fi
[ -f "$OUT/disk.img" ] || { echo "kein disk.img"; exit 1; }
. tools/lib/treekey.sh
BUILDD=${LOOKBUILD:-$(osum_keyed_builddir /tmp/osum-lookbuild .)}
[ -f "$BUILDD/k0.mb" ] || { echo "kein Kern in $BUILDD"; exit 1; }
ok "Abbild und Kern stehen"

echo "== 2. start Osum and open settings =="
rm -f "$OUT/serial.txt" "$SOCK"
cp "$OUT/disk.img" "$OUT/lauf.img"
timeout 420 qemu-system-x86_64 -kernel "$BUILDD/k0.mb" -m 512 \
    -append "gfx wm wig wigicons desk wmhold wiglong nokbd nosched noproc nofs fbres=1280x800" \
    -serial "file:$OUT/serial.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/lauf.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >"$OUT/qemu.log" 2>&1 &
QPID=$!

i=0
while [ $i -lt 2400 ]; do
    grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null && break
    kill -0 "$QPID" 2>/dev/null || break
    sleep 0.15; i=$((i+1))
done
if grep -qaE '^wm: hold' "$OUT/serial.txt" 2>/dev/null; then
    ok "the desktop is up"
else
    bad "the desktop did not come up"
    tail -8 "$OUT/serial.txt" 2>/dev/null | sed 's/^/        /'
    echo "REITER: $pass bestanden, $fail durchgefallen"; exit 1
fi

klick() {
    python3 tools/themestore/click.py "$1" > "$OUT/k.txt" 2>/dev/null || return 1
    python3 tools/wm/monitor.py "$SOCK" "$OUT/k.txt" >/dev/null 2>&1 || return 1
    sleep "${2:-2}"
    return 0
}

klick 20,786 2
MENU_X=8
MENU_Y=312
SETTINGS_ROW_DX=200
SETTINGS_ROW_DY=218
note "start menu at $MENU_X,$MENU_Y -- settings row at $((MENU_X+SETTINGS_ROW_DX)),$((MENU_Y+SETTINGS_ROW_DY))"
klick "$((MENU_X+SETTINGS_ROW_DX)),$((MENU_Y+SETTINGS_ROW_DY))" 3
sleep 2

if grep -qa 'settings: stand' "$OUT/serial.txt" 2>/dev/null; then
    ok "settings laeuft"
    note "$(grep -a 'settings: elemente' "$OUT/serial.txt" | tail -1)"
else
    bad "settings did not open"
    grep -aE 'launcher:|settings:' "$OUT/serial.txt" | tail -6 | sed 's/^/        /'
fi

echo "== 3. click the bridge tab =="
STAND_VOR=$(grep -a 'settings: stand' "$OUT/serial.txt" | tail -1)
klick 700,150 2
STAND_NACH=$(grep -a 'settings: stand' "$OUT/serial.txt" | tail -1)
note "vorher: $STAND_VOR"
note "nachher: $STAND_NACH"

echo "== 4. das Bild =="
python3 tools/wm/monitor.py "$SOCK" /dev/stdin >/dev/null 2>&1 <<CMD
screendump $OUT/reiter.ppm
CMD
sleep 2
if [ -s "$OUT/reiter.ppm" ]; then
    python3 - "$OUT/reiter.ppm" "$OUT/reiter.png" <<'PYEOF'
import sys, zlib, struct
roh = open(sys.argv[1], "rb").read()
# P6\n<w> <h>\n255\n
teile = roh.split(b"\n", 3)
w, h = [int(x) for x in teile[1].split()]
pix = teile[3]
zeilen = b""
for y in range(h):
    zeilen += b"\x00" + pix[y * w * 3:(y + 1) * w * 3]
def stueck(t, d):
    return (struct.pack(">I", len(d)) + t + d
            + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF))
png = (b"\x89PNG\r\n\x1a\n"
       + stueck(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + stueck(b"IDAT", zlib.compress(zeilen, 6))
       + stueck(b"IEND", b""))
open(sys.argv[2], "wb").write(png)
print("%dx%d, %d Oktette" % (w, h, len(png)))
PYEOF
    ok "Bild gemacht: $OUT/reiter.png"
else
    bad "kein Bild"
fi

echo
echo "REITER: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ] || exit 1
