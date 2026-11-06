#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1   # r1223: QEMU -kernel/-initrd has no boot medium; the installer needs /boot/osum.mb in the root
. tools/lib/qemu.sh

BAU=${1:-/tmp/dual-img}
OUT=${2:-/tmp/dual-abnahme}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/lock.sh" && osum_sperre "$OUT"   # A-024
mkdir -p "$OUT"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }
titel() { printf '\n=== %s\n' "$*"; }

[ -f "$BAU/osum.mb" ]  || { echo "== $BAU/osum.mb fehlt"  >&2; exit 1; }
[ -f "$BAU/root.img" ] || { echo "== $BAU/root.img fehlt" >&2; exit 1; }

read_layout() {
    local img=$1 end
    ESP_START=$(sgdisk -i 1 "$img" 2>/dev/null | sed -n 's/First sector: \([0-9]*\).*/\1/p')
    end=$(sgdisk -i 1 "$img" 2>/dev/null | sed -n 's/Last sector: \([0-9]*\).*/\1/p')
    ESP_SEK=$((end - ESP_START + 1))
    DAT_START=$(sgdisk -i 2 "$img" 2>/dev/null | sed -n 's/First sector: \([0-9]*\).*/\1/p')
    end=$(sgdisk -i 2 "$img" 2>/dev/null | sed -n 's/Last sector: \([0-9]*\).*/\1/p')
    DAT_SEK=$((end - DAT_START + 1))
}

esp_summe()   { dd if="$1" bs=512 skip=$ESP_START count=$ESP_SEK status=none | sha256sum | cut -d' ' -f1; }
daten_summe() { dd if="$1" bs=512 skip=$DAT_START count=$DAT_SEK status=none | sha256sum | cut -d' ' -f1; }

# ==================================================================
titel "1. eine Platte, auf der schon jemand wohnt"
# ==================================================================
bash tools/dual/fremdplatte.sh "$OUT/platte.img" 512 | sed 's/^/   /'
[ -f "$OUT/platte.img" ] || { echo "the disk was not built" >&2; exit 1; }

read_layout "$OUT/platte.img"
VOR_ESP=$(esp_summe   "$OUT/platte.img")
BEFORE_DAT=$(daten_summe "$OUT/platte.img")
echo "   VORHER  esp   $VOR_ESP"
echo "   BEFORE  data $BEFORE_DAT"

sgdisk -p "$OUT/platte.img" > "$OUT/gpt-vorher.txt" 2>&1
grep -qE "^ +1 +$ESP_START" "$OUT/gpt-vorher.txt" && ok "the foreign disk carries an ESP" \
    || bad "the foreign disk has no ESP"
grep -qE "^ +2 +$DAT_START" "$OUT/gpt-vorher.txt" && ok "the foreign disk carries a data partition" \
    || bad "the foreign disk has no data partition"

# ==================================================================
titel "2. ${MARKE_PRODUKT} in den freien Platz installieren"
# ==================================================================
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=1800 nokbd nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,now,beside"

timeout "${LIMIT:-1800}" $QEMU_X86 -m 512 \
    -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$OUT/ser.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -drive "file=$OUT/platte.img,format=raw,if=ide,index=0" \
    > "$OUT/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 1800 ]; do
    grep -qa 'installer: done\|installer: ERROR\|installer: BESIDE_NO' "$OUT/ser.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 4
kill "$QP" 2>/dev/null
wait "$QP" 2>/dev/null

echo "   what the program saw and did:"
grep -aE '^installer: (disk|ready|tafel=|part |frei |fremdesp=|weg=|neuepart|esp=|menue=|step=|fertig|FEHLER|NEBENNEIN|bei=)' \
    "$OUT/ser.txt" 2>/dev/null | head -30 | sed 's/^/        /'

grep -qa 'installer: table=2' "$OUT/ser.txt" \
    && ok "it read the foreign partition table (2 partitions)" \
    || bad "the foreign partition table was not read"
grep -qa 'installer: foreign_esp=1' "$OUT/ser.txt" \
    && ok "it found the existing EFI partition" \
    || bad "the existing EFI partition was not found"
grep -qa 'installer: newpart' "$OUT/ser.txt" \
    && ok "it added a new partition entry" \
    || bad "no partition entry was added"
grep -qa 'installer: done' "$OUT/ser.txt" \
    && ok "the installation reports done" \
    || bad "the installation did not finish"

# ==================================================================
titel "3. DIE FREMDEN PARTITIONEN -- BYTEWEISE UNVERAENDERT?"
# ==================================================================
NACH_ESP=$(esp_summe   "$OUT/platte.img")
AFTER_DAT=$(daten_summe "$OUT/platte.img")
echo "   NACHHER esp   $NACH_ESP"
echo "   AFTER   data $AFTER_DAT"

if [ "$BEFORE_DAT" = "$AFTER_DAT" ]; then
    ok "THE FOREIGN DATA PARTITION IS UNCHANGED BYTE FOR BYTE"
else
    bad "the foreign data partition was changed -- ${BEFORE_DAT:0:16}… -> ${AFTER_DAT:0:16}…"
fi

if [ "$VOR_ESP" = "$NACH_ESP" ]; then
    echo "   (the ESP is unchanged -- so ${MARKE_PRODUKT} stored nothing there)"
fi

# ==================================================================
titel "4. die Dateien des fremden Systems in der ESP"
# ==================================================================
ESPOFF=$((ESP_START * 512))
mdir -i "$OUT/platte.img@@$ESPOFF" ::/EFI/Microsoft/Boot > "$OUT/esp-fremd.txt" 2>&1
sed 's/^/        /' "$OUT/esp-fremd.txt" | head -10
grep -qi 'bootmgfw' "$OUT/esp-fremd.txt" \
    && ok "THE FOREIGN BOOT MANAGER (bootmgfw.efi) IS STILL THERE" \
    || bad "bootmgfw.efi has disappeared -- the foreign boot loader was deleted"
grep -qi 'BCD' "$OUT/esp-fremd.txt" \
    && ok "the foreign file BCD in the ESP is still there" \
    || bad "the foreign file BCD has disappeared"

mdir -i "$OUT/platte.img@@$ESPOFF" ::"/EFI/${MARKE_KURZ}" > "$OUT/esp-osum.txt" 2>&1
sed 's/^/        /' "$OUT/esp-osum.txt" | head -8
grep -qi 'osum' "$OUT/esp-osum.txt" \
    && ok "${MARKE_PRODUKT} lives in its own directory /EFI/${MARKE_KURZ}" \
    || bad "nothing is under /EFI/${MARKE_KURZ}"

# ==================================================================
titel "5. ist die GPT gueltig? -- mit FREMDEN Augen gelesen"
# ==================================================================
sgdisk -v "$OUT/platte.img" > "$OUT/gpt-pruef.txt" 2>&1
sgdisk -p "$OUT/platte.img" > "$OUT/gpt-nachher.txt" 2>&1
sed 's/^/        /' "$OUT/gpt-nachher.txt" | tail -8
if grep -qi 'No problems found' "$OUT/gpt-pruef.txt"; then
    ok "sgdisk sagt: No problems found (beide Koepfe, beide CRC32)"
else
    bad "sgdisk complains about the table:"
    sed 's/^/          /' "$OUT/gpt-pruef.txt" | head -8
fi
n=$(grep -cE '^ +[0-9]+ +[0-9]+' "$OUT/gpt-nachher.txt" || true)
[ "${n:-0}" -ge 3 ] && ok "the table now has $n partitions (before: 2)" \
    || bad "the table has only ${n:-0} partitions"
grep -qi 'OSUM' "$OUT/gpt-nachher.txt" \
    && ok "the new partition is named OSUM" \
    || bad "keine Partition namens OSUM"

python3 tools/dual/tafelpruef.py "$OUT/platte.img" > "$OUT/tafelpruef.txt" 2>&1
TPRC=$?
sed 's/^/        /' "$OUT/tafelpruef.txt"
[ "$TPRC" = 0 ] && ok "the independent checker confirms both headers and both table sums" \
    || bad "the independent checker complains about the table"

# ==================================================================
titel "6. bietet das Bootmenue beide Systeme an?"
# ==================================================================
mtype -i "$OUT/platte.img@@$ESPOFF" ::/limine.conf > "$OUT/limine.txt" 2>&1
sed 's/^/        /' "$OUT/limine.txt" | head -14
grep -qi "${MARKE_PRODUKT}" "$OUT/limine.txt" \
    && ok "the boot menu has an entry for ${MARKE_PRODUKT}" \
    || bad "the boot menu lacks ${MARKE_PRODUKT}"
if grep -qi 'efi_chainload' "$OUT/limine.txt" && grep -qi 'bootmgfw' "$OUT/limine.txt"; then
    ok "THE BOOT MENU HAS AN ENTRY FOR THE FOREIGN SYSTEM (chain start)"
else
    bad "the boot menu lacks the entry for the foreign system"
fi

printf '\n=======================================================\n'
printf 'DUALBOOT-ABNAHME:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
