#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dual/startprobe.sh -- STARTET DIE PLATTE WIRKLICH? UND ZEIGT DAS
# MENUE BEIDE SYSTEME?
#
#   bash tools/dual/startprobe.sh <platte.img> [ausgabeverzeichnis]
#
# ==================================================================
# WARUM DIESER LAUF SEPARAT STEHT
# ==================================================================
#
# Die Abnahme (`abnahme-cli.sh`) prueft, was auf der PLATTE steht: die
# Tafel, die Pruefsummen, die Dateien, die Startdatei. Das ist die
# Zusage ueber die Daten, und sie ist die wichtigere.
#
# Sie sagt aber noch nichts darueber, ob die Firmware damit auch etwas
# anfangen kann. Ein Bootmenue, das in einer Datei richtig aussieht und
# auf dem Schirm nie erscheint, hat niemandem geholfen.
#
# Also: OVMF, KEIN `-kernel`, KEIN `-initrd`, KEIN Installationsmedium.
# Nur die Platte. Was jetzt erscheint, kommt von dieser Platte -- oder
# es erscheint nichts.
#
# Gemessen wird mit einem Foto und `tesseract`: stehen BEIDE Namen im
# Menue? Das ist der einzige Weg, eine Bildschirmausgabe des Bootladers
# zu pruefen -- er schreibt nicht auf die serielle Leitung, bevor ein
# Eintrag gewaehlt ist.
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

# KEIN -kernel, KEIN -initrd. Nur OVMF und die Platte.
qemu-system-x86_64 -accel tcg -m 512 \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$CODE" \
    -drive "if=pflash,format=raw,unit=1,file=$OUT/vars.fd" \
    -drive "file=$IMG,format=raw,if=ide,index=0" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$OUT/mon,server,nowait" > "$OUT/qemu.log" 2>&1 &
QP=$!

for i in $(seq 1 60); do [ -S "$OUT/mon" ] && break; sleep 1; done
# Das Menue steht `timeout: 10` Sekunden. Nach acht Sekunden fotografieren.
sleep "${WARTE:-10}"
printf 'screendump %s/menue.ppm\n' "$OUT" | socat - "UNIX-CONNECT:$OUT/mon" >/dev/null 2>&1
sleep 3
# Und danach weiterlaufen lassen, bis OrientOS gestartet ist.
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

echo "== das Bootmenue, wie es auf dem Schirm steht"
if [ -s "$OUT/menue.png" ]; then
    tesseract "$OUT/menue.png" - 2>/dev/null | grep -v '^\s*$' | head -12 | sed 's/^/        /'
    TXT=$(tesseract "$OUT/menue.png" - 2>/dev/null)
    echo "$TXT" | grep -qi 'orientos' \
        && ok "OrientOS steht im Bootmenue AUF DEM SCHIRM" \
        || bad "OrientOS steht nicht im Menue"
    echo "$TXT" | grep -qi 'windows' \
        && ok "DAS FREMDE SYSTEM STEHT IM BOOTMENUE AUF DEM SCHIRM" \
        || bad "das fremde System steht nicht im Menue"
    echo "$TXT" | grep -qi 'limine' \
        && ok "der Bootlader laeuft VON DER PLATTE (kein Medium im Spiel)" \
        || bad "kein Bootlader auf dem Schirm"
else
    bad "kein Foto vom Bootmenue"
fi

echo
echo "== was danach auf der seriellen Leitung steht"
tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -aE '^(osum|wm|init|desk):' | head -12 | sed 's/^/        /'
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qaE '^(osum|wm|desk):'; then
    ok "ORIENTOS STARTET VON DER PLATTE"
else
    bad "OrientOS ist nicht gestartet"
fi
# UND ES FINDET SEINE WURZEL AUF DER NEU ANGELEGTEN PARTITION.
# `wm: rootpart=` nennt die Nummer und den ersten Sektor -- genau die
# Zahlen, die `neben_schreiben` in die fremde Tafel geschrieben hat.
RP=$(tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -aoE 'rootpart=[0-9]+  first=[0-9]+' | head -1)
if [ -n "$RP" ]; then
    ok "es findet seine Wurzel in der neuen Partition ($RP)"
else
    bad "die Wurzel der neuen Partition wurde nicht gefunden"
fi
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qa 'desk: start /bin/desktop'; then
    ok "der Schreibtisch startet"
else
    bad "der Schreibtisch startet nicht"
fi
# Die Gegenprobe: es darf KEIN Boot-Modul im Spiel sein.
if tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -qa 'from module'; then
    bad "die Wurzel kam als Boot-Modul -- das war kein Start von der Platte"
else
    ok "die Wurzel kam NICHT als Boot-Modul (kein Installationsmedium)"
fi

printf '\n=======================================================\n'
printf 'START VON DER PLATTE:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
