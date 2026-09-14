#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dual/kettenprobe.sh -- STARTET DER ZWEITE EINTRAG WIRKLICH DAS
# FREMDE SYSTEM?
#
#   bash tools/dual/kettenprobe.sh <platte.img> [ausgabeverzeichnis]
#
# ==================================================================
# WAS HIER GEMESSEN WIRD, UND WARUM ES NICHT GENUEGT, DASS DER EINTRAG
# IM MENUE STEHT
# ==================================================================
#
# `startprobe.sh` zeigt, dass "Windows Boot Manager" auf dem Schirm
# steht. Das ist eine Aussage ueber eine Zeile Text. Ob dahinter auch
# etwas passiert, wenn man sie waehlt, ist eine andere Frage -- und es
# ist die, auf die es ankommt: ein Menueeintrag, der ins Leere fuehrt,
# ist schlimmer als keiner, weil er wie ein Weg zurueck ins alte System
# aussieht.
#
# Deshalb liegt an der Stelle, an der auf einem echten Rechner
# \EFI\Microsoft\Boot\bootmgfw.efi liegt, eine ECHTE, winzige
# UEFI-Anwendung (tools/dual/beweis.c), die sich SELBST zu erkennen
# gibt: sie schreibt auf COM1 und auf den EFI-Schirm einen Satz, den
# sonst niemand schreibt.
#
# WARUM NICHT EINFACH EINE ZWEITE KOPIE VON LIMINE: sie sucht dieselbe
# Konfiguration wie die erste und ist von ihr nicht zu unterscheiden --
# der Schirm bleibt schwarz, und das sieht wie ein Fehlschlag aus,
# obwohl der Kettenstart lief. Gemessen in dieser Runde, eine Stunde
# lang.
#
# Der zweite Eintrag wird mit der PFEILTASTE gewaehlt, wie ein Mensch
# es taete.
set -uo pipefail
cd "$(dirname "$0")/../.."

IMG=${1:?platte.img fehlt}
OUT=${2:-/root/dualwork/kette}
mkdir -p "$OUT"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }

CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$CODE" ] || { CODE=/usr/share/OVMF/OVMF_CODE.fd; VARS=/usr/share/OVMF/OVMF_VARS.fd; }
cp -f "$VARS" "$OUT/vars.fd"
cp -f "$IMG" "$OUT/platte.img"
rm -f "$OUT/mon" "$OUT/ser.txt" "$OUT/kette.ppm" "$OUT/kette.png"

mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$OUT/mon" >/dev/null 2>&1; }

qemu-system-x86_64 -accel tcg -m 512 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$OUT/vars.fd" \
    -drive "file=$OUT/platte.img,format=raw,if=ide,index=0" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$OUT/mon,server,nowait" > "$OUT/qemu.log" 2>&1 &
QP=$!

for i in $(seq 1 60); do [ -S "$OUT/mon" ] && break; sleep 1; done
sleep "${WARTE:-4}"

# 1. Irgendeine Taste haelt den Countdown an.
mon 'sendkey spc'
sleep 2
# 2. Pfeil nach unten: der ZWEITE Eintrag.
mon 'sendkey down'
sleep 2
mon "screendump $OUT/wahl.ppm"
sleep 2
# 3. Und starten.
mon 'sendkey ret'
sleep "${KETTE_WARTE:-18}"
mon "screendump $OUT/kette.ppm"
sleep 3
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

for n in wahl kette; do
    [ -s "$OUT/$n.ppm" ] || continue
    python3 -c "
from PIL import Image
Image.open('$OUT/$n.ppm').save('$OUT/$n.png')
" 2>/dev/null && rm -f "$OUT/$n.ppm"
done

echo "== was nach dem Kettenstart auf dem Schirm steht"
if [ -s "$OUT/kette.png" ]; then
    tesseract "$OUT/kette.png" - 2>/dev/null | grep -v '^\s*$' | head -8 | sed 's/^/        /'
fi
echo "== und auf der seriellen Leitung"
tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -a 'BEWEIS' | head -3 | sed 's/^/        /'

# DER BELEG: der fremde Bootmanager meldet sich selbst.
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qa 'KETTENSTART HAT FUNKTIONIERT'; then
    ok "DER KETTENSTART LAEUFT -- der fremde Bootmanager meldet sich"
else
    bad "der fremde Bootmanager hat sich nicht gemeldet"
fi
if [ -s "$OUT/kette.png" ] && tesseract "$OUT/kette.png" - 2>/dev/null | grep -qi 'KETTENSTART'; then
    ok "und er steht auch AUF DEM SCHIRM"
else
    bad "auf dem Schirm steht er nicht"
fi
# Gegenprobe: OrientOS darf NICHT gestartet sein.
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qa 'desk: start'; then
    bad "es hat OrientOS gestartet statt des fremden Systems"
else
    ok "OrientOS wurde NICHT gestartet -- es war wirklich der zweite Eintrag"
fi

printf '\n=======================================================\n'
printf 'KETTENSTART:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
