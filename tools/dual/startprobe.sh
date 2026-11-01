#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
set -uo pipefail
cd "$(dirname "$0")/../.."

IMG=${1:?platte.img fehlt}
OUT=${2:-/root/dualwork/start}
mkdir -p "$OUT"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }

CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$CODE" ] || { CODE=/usr/share/OVMF/OVMF_CODE.fd; VARS=/usr/share/OVMF/OVMF_VARS.fd; }
cp -f "$VARS" "$OUT/vars.fd"

rm -f "$OUT/mon" "$OUT/menue.ppm" "$OUT/menue.png" "$OUT/ser.txt"

qemu-system-x86_64 -accel tcg -m 512 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$OUT/vars.fd" \
    -drive "file=$IMG,format=raw,if=ide,index=0" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$OUT/mon,server,nowait" > "$OUT/qemu.log" 2>&1 &
QP=$!

for i in $(seq 1 60); do [ -S "$OUT/mon" ] && break; sleep 1; done
sleep "${WARTE:-3}"
printf 'screendump %s/menue.ppm\n' "$OUT" | socat - "UNIX-CONNECT:$OUT/mon" >/dev/null 2>&1
sleep 3
sleep "${LANG_WARTE:-40}"
printf 'screendump %s/danach.ppm\n' "$OUT" | socat - "UNIX-CONNECT:$OUT/mon" >/dev/null 2>&1
sleep 3
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

for n in menue danach; do
    [ -s "$OUT/$n.ppm" ] || continue
    python3 -c "
from PIL import Image
Image.open('$OUT/$n.ppm').save('$OUT/$n.png')
" 2>/dev/null && rm -f "$OUT/$n.ppm"
done

echo "== the boot menu as it appears on the screen"
if [ -s "$OUT/menue.png" ]; then
    tesseract "$OUT/menue.png" - 2>/dev/null | grep -v '^\s*$' | head -12 | sed 's/^/        /'
    TXT=$(tesseract "$OUT/menue.png" - 2>/dev/null)
    echo "$TXT" | grep -qi "$MARKE_PRODUKT" \
        && ok "${MARKE_PRODUKT} is in the boot menu ON THE SCREEN" \
        || bad "${MARKE_PRODUKT} is not in the menu"
    echo "$TXT" | grep -qi 'windows' \
        && ok "THE FOREIGN SYSTEM IS IN THE BOOT MENU ON THE SCREEN" \
        || bad "the foreign system is not in the menu"
    echo "$TXT" | grep -qi 'limine' \
        && ok "the boot loader runs FROM THE DISK (no medium involved)" \
        || bad "no boot loader on the screen"
else
    bad "no photo of the boot menu"
fi

echo
echo "== what is on the serial line afterwards"
tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -aE '^(osum|wm|init|desk):' | head -12 | sed 's/^/        /'
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qaE '^(osum|wm|desk):'; then
    ok "${MARKE_PRODUKT^^} STARTS FROM THE DISK"
else
    bad "${MARKE_PRODUKT} did not start"
fi
RP=$(tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -aoE 'rootpart=[0-9]+  first=[0-9]+' | head -1)
if [ -n "$RP" ]; then
    ok "it finds its root in the new partition ($RP)"
else
    bad "the root of the new partition was not found"
fi
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qa 'desk: start /bin/desktop'; then
    ok "der Schreibtisch startet"
else
    bad "the desktop does not start"
fi
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qa 'from module'; then
    bad "the root came as a boot module -- that was no start from the disk"
else
    ok "the root did NOT come as a boot module (no installation medium)"
fi

printf '\n=======================================================\n'
printf 'START VON DER PLATTE:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
