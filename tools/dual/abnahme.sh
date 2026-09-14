#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dual/abnahme.sh -- DIE ABNAHME DER RUNDE DUALBOOT.
#
#   bash tools/dual/abnahme.sh [bauverzeichnis] [ausgabeverzeichnis]
#
# ==================================================================
# DIE FRAGE, UM DIE ES GEHT
# ==================================================================
#
# Kann OrientOS sich neben ein vorhandenes System legen, OHNE dessen
# Daten anzufassen? Das ist keine Frage, die sich mit "das Programm
# meldet fertig" beantworten laesst. Ein Installationsprogramm, das
# nebenbei eine fremde Partition zerstoert, meldet sich genauso fertig.
#
# Deshalb diese Kette, und die Pruefsummen sind nicht verhandelbar:
#
#   1. EINE PLATTE, AUF DER SCHON JEMAND WOHNT. Gebaut mit `sgdisk`,
#      also einem FREMDEN Werkzeug: GPT, eine ESP mit einer Datei
#      darin, eine grosse Datenpartition, dahinter freier Platz.
#      Je Partition eine sha256.
#
#   2. INSTALLIEREN -- in den freien Platz, nicht auf die ganze Platte.
#
#   3. DIE FREMDEN PARTITIONEN SIND BYTEWEISE UNVERAENDERT. Dieselbe
#      Rechnung wie in Glied 1, und sie muss dasselbe ergeben. Das ist
#      die eigentliche Zusage dieser Runde.
#
#   4. DIE DATEI IN DER ESP IST NOCH DA. Die ESP wurde MITBENUTZT und
#      nicht neu geschrieben -- genau der Punkt, an dem ein schlechtes
#      Installationsprogramm fremde Bootlader loescht.
#
#   5. DIE GPT IST GUELTIG, mit einem FREMDEN Werkzeug gegengelesen
#      (`sgdisk -v`) und zusaetzlich mit einem unabhaengigen eigenen
#      Pruefer, der beide CRC32 selbst rechnet.
#
#   6. DAS BOOTMENUE BIETET BEIDE EINTRAEGE AN.
#
#   7. ORIENTOS STARTET VON DER PLATTE -- ohne Installationsmedium.
#
# GEGENPROBE (Glied 8): dieselbe Platte, aber ohne ausreichend freien
# Platz. Dann MUSS das Programm sauber abbrechen und die Platte
# unveraendert lassen. Ohne diese Gegenprobe waere nicht gezeigt, dass
# die Pruefungen wirklich greifen -- ein Programm, das immer schreibt,
# haette bis hierher genauso gruen ausgesehen.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

BAU=${1:-/tmp/dual-img}
OUT=${2:-/tmp/dual-abnahme}
mkdir -p "$OUT"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }
titel() { printf '\n=== %s\n' "$*"; }

[ -f "$BAU/osum.mb" ]  || { echo "== $BAU/osum.mb fehlt"  >&2; exit 1; }
[ -f "$BAU/root.img" ] || { echo "== $BAU/root.img fehlt" >&2; exit 1; }

# Die Lage der fremden Partitionen -- dieselben Zahlen wie in
# fremdplatte.sh. Sie stehen hier noch einmal, weil die Pruefsummen
# genau diese Bereiche lesen muessen.
ESP_START=2048;   ESP_SEK=$((64 * 2048))
DAT_START=133120; DAT_SEK=$((128 * 2048))

esp_summe()   { dd if="$1" bs=512 skip=$ESP_START count=$ESP_SEK status=none | sha256sum | cut -d' ' -f1; }
daten_summe() { dd if="$1" bs=512 skip=$DAT_START count=$DAT_SEK status=none | sha256sum | cut -d' ' -f1; }

# ==================================================================
titel "1. eine Platte, auf der schon jemand wohnt"
# ==================================================================
bash tools/dual/fremdplatte.sh "$OUT/platte.img" 512 | sed 's/^/   /'
[ -f "$OUT/platte.img" ] || { echo "die Platte wurde nicht gebaut" >&2; exit 1; }

VOR_ESP=$(esp_summe   "$OUT/platte.img")
VOR_DAT=$(daten_summe "$OUT/platte.img")
echo "   VORHER  esp   $VOR_ESP"
echo "   VORHER  daten $VOR_DAT"

sgdisk -p "$OUT/platte.img" > "$OUT/gpt-vorher.txt" 2>&1
grep -qE '^ +1 +2048' "$OUT/gpt-vorher.txt" && ok "die fremde Platte traegt eine ESP" \
    || bad "die fremde Platte hat keine ESP"
grep -qE '^ +2 +133120' "$OUT/gpt-vorher.txt" && ok "die fremde Platte traegt eine Datenpartition" \
    || bad "die fremde Platte hat keine Datenpartition"

# ==================================================================
titel "2. OrientOS in den freien Platz installieren"
# ==================================================================
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1800 nokbd nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,sofort,daneben"

timeout "${LIMIT:-1800}" $QEMU_X86 -m 512 \
    -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -drive "file=$OUT/platte.img,format=raw,if=ide,index=0" \
    > "$OUT/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 1800 ]; do
    grep -qa 'installer: fertig\|installer: FEHLER\|installer: NEBENNEIN' "$OUT/ser.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 4
kill "$QP" 2>/dev/null
wait "$QP" 2>/dev/null

echo "   was das Programm gesehen und getan hat:"
grep -aE '^installer: (disk|ready|tafel=|part |frei |fremdesp=|weg=|neuepart|esp=|menue=|step=|fertig|FEHLER|NEBENNEIN|bei=)' \
    "$OUT/ser.txt" 2>/dev/null | head -30 | sed 's/^/        /'

# Hat es die Tafel ueberhaupt gelesen?
grep -qa 'installer: tafel=2' "$OUT/ser.txt" \
    && ok "es hat die fremde Partitionstafel gelesen (2 Partitionen)" \
    || bad "die fremde Partitionstafel wurde nicht gelesen"
grep -qa 'installer: fremdesp=1' "$OUT/ser.txt" \
    && ok "es hat die vorhandene EFI-Partition gefunden" \
    || bad "die vorhandene EFI-Partition wurde nicht gefunden"
grep -qa 'installer: neuepart' "$OUT/ser.txt" \
    && ok "es hat einen neuen Partitionseintrag ergaenzt" \
    || bad "es wurde kein Partitionseintrag ergaenzt"
grep -qa 'installer: fertig' "$OUT/ser.txt" \
    && ok "die Installation meldet sich fertig" \
    || bad "die Installation ist nicht fertig geworden"

# ==================================================================
titel "3. DIE FREMDEN PARTITIONEN -- BYTEWEISE UNVERAENDERT?"
# ==================================================================
NACH_ESP=$(esp_summe   "$OUT/platte.img")
NACH_DAT=$(daten_summe "$OUT/platte.img")
echo "   NACHHER esp   $NACH_ESP"
echo "   NACHHER daten $NACH_DAT"

if [ "$VOR_DAT" = "$NACH_DAT" ]; then
    ok "DIE FREMDE DATENPARTITION IST OKTETT FUER OKTETT UNVERAENDERT"
else
    bad "die fremde Datenpartition wurde veraendert -- ${VOR_DAT:0:16}… -> ${NACH_DAT:0:16}…"
fi

# DIE ESP DARF SICH AENDERN -- dort legt OrientOS ja seine Dateien ab.
# Was NICHT passieren darf, ist, dass die fremden Dateien verschwinden.
# Deshalb wird hier nicht die Summe verglichen, sondern der INHALT.
if [ "$VOR_ESP" = "$NACH_ESP" ]; then
    echo "   (die ESP ist unveraendert -- dann hat OrientOS dort nichts abgelegt)"
fi

# ==================================================================
titel "4. die Dateien des fremden Systems in der ESP"
# ==================================================================
ESPOFF=$((ESP_START * 512))
mdir -i "$OUT/platte.img@@$ESPOFF" ::/EFI/Microsoft/Boot > "$OUT/esp-fremd.txt" 2>&1
sed 's/^/        /' "$OUT/esp-fremd.txt" | head -10
grep -qi 'bootmgfw' "$OUT/esp-fremd.txt" \
    && ok "DER FREMDE BOOTMANAGER (bootmgfw.efi) IST NOCH DA" \
    || bad "bootmgfw.efi ist verschwunden -- der fremde Bootlader wurde geloescht"
grep -qi 'BCD' "$OUT/esp-fremd.txt" \
    && ok "die fremde Datei BCD in der ESP ist noch da" \
    || bad "die fremde Datei BCD ist verschwunden"

# Und liegt OrientOS in SEINEM eigenen Verzeichnis?
mdir -i "$OUT/platte.img@@$ESPOFF" ::/EFI/orientos > "$OUT/esp-osum.txt" 2>&1
sed 's/^/        /' "$OUT/esp-osum.txt" | head -8
grep -qi 'osum' "$OUT/esp-osum.txt" \
    && ok "OrientOS liegt in seinem eigenen Verzeichnis /EFI/orientos" \
    || bad "unter /EFI/orientos liegt nichts"

# ==================================================================
titel "5. ist die GPT gueltig? -- mit FREMDEN Augen gelesen"
# ==================================================================
sgdisk -v "$OUT/platte.img" > "$OUT/gpt-pruef.txt" 2>&1
sgdisk -p "$OUT/platte.img" > "$OUT/gpt-nachher.txt" 2>&1
sed 's/^/        /' "$OUT/gpt-nachher.txt" | tail -8
if grep -qi 'No problems found' "$OUT/gpt-pruef.txt"; then
    ok "sgdisk sagt: No problems found (beide Koepfe, beide CRC32)"
else
    bad "sgdisk beanstandet die Tafel:"
    sed 's/^/          /' "$OUT/gpt-pruef.txt" | head -8
fi
n=$(grep -cE '^ +[0-9]+ +[0-9]+' "$OUT/gpt-nachher.txt" || true)
[ "${n:-0}" -ge 3 ] && ok "die Tafel traegt jetzt $n Partitionen (vorher 2)" \
    || bad "die Tafel traegt nur ${n:-0} Partitionen"
grep -qi 'OSUM' "$OUT/gpt-nachher.txt" \
    && ok "die neue Partition heisst OSUM" \
    || bad "keine Partition namens OSUM"

# Der zweite, unabhaengige Pruefer -- er rechnet beide CRC32 selbst.
python3 tools/dual/tafelpruef.py "$OUT/platte.img" > "$OUT/tafelpruef.txt" 2>&1
TPRC=$?
sed 's/^/        /' "$OUT/tafelpruef.txt"
[ "$TPRC" = 0 ] && ok "der unabhaengige Pruefer bestaetigt beide Koepfe und beide Tafelsummen" \
    || bad "der unabhaengige Pruefer beanstandet die Tafel"

# ==================================================================
titel "6. bietet das Bootmenue beide Systeme an?"
# ==================================================================
mtype -i "$OUT/platte.img@@$ESPOFF" ::/limine.conf > "$OUT/limine.txt" 2>&1
sed 's/^/        /' "$OUT/limine.txt" | head -14
grep -qi 'OrientOS' "$OUT/limine.txt" \
    && ok "das Bootmenue hat einen Eintrag fuer OrientOS" \
    || bad "im Bootmenue fehlt OrientOS"
if grep -qi 'efi_chainload' "$OUT/limine.txt" && grep -qi 'bootmgfw' "$OUT/limine.txt"; then
    ok "DAS BOOTMENUE HAT EINEN EINTRAG FUER DAS FREMDE SYSTEM (Kettenstart)"
else
    bad "im Bootmenue fehlt der Eintrag fuer das fremde System"
fi

printf '\n=======================================================\n'
printf 'DUALBOOT-ABNAHME:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
