#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

BAU=${1:-/root/dualwork/img}
OUT=${2:-/root/dualwork/cli}
mkdir -p "$OUT"

ok=0; bad=0
ok()  { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
bad() { printf '  [FEHL] %s\n' "$*"; bad=$((bad+1)); }
titel() { printf '\n=== %s\n' "$*"; }

[ -f "$BAU/osum.mb" ]  || { echo "== $BAU/osum.mb fehlt"  >&2; exit 1; }
[ -f "$BAU/root.img" ] || { echo "== $BAU/root.img fehlt" >&2; exit 1; }

lies_lage() {
    local img=$1
    ESP_START=$(sgdisk -i 1 "$img" 2>/dev/null | sed -n 's/First sector: \([0-9]*\).*/\1/p')
    local esp_end
    esp_end=$(sgdisk -i 1 "$img" 2>/dev/null | sed -n 's/Last sector: \([0-9]*\).*/\1/p')
    ESP_SEK=$((esp_end - ESP_START + 1))
    DAT_START=$(sgdisk -i 2 "$img" 2>/dev/null | sed -n 's/First sector: \([0-9]*\).*/\1/p')
    local dat_end
    dat_end=$(sgdisk -i 2 "$img" 2>/dev/null | sed -n 's/Last sector: \([0-9]*\).*/\1/p')
    DAT_SEK=$((dat_end - DAT_START + 1))
    ESPOFF=$((ESP_START * 512))
}

esp_summe()   { dd if="$1" bs=512 skip=$ESP_START count=$ESP_SEK status=none | sha256sum | cut -d' ' -f1; }
daten_summe() { dd if="$1" bs=512 skip=$DAT_START count=$DAT_SEK status=none | sha256sum | cut -d' ' -f1; }

. tools/dual/lib-cli.sh

# ==================================================================
titel "1. eine Platte, auf der schon jemand wohnt"
# ==================================================================
bash tools/dual/fremdplatte.sh "$OUT/platte.img" 80 | sed 's/^/   /'
lies_lage "$OUT/platte.img"
echo "   gemessen: ESP $ESP_START+$ESP_SEK, Daten $DAT_START+$DAT_SEK"
VOR_ESP=$(esp_summe   "$OUT/platte.img")
VOR_DAT=$(daten_summe "$OUT/platte.img")
echo "   VORHER  esp   $VOR_ESP"
echo "   BEFORE  data $VOR_DAT"

# ==================================================================
titel "2. der Probelauf -- versteht es die fremde Platte?"
cp -f "$OUT/platte.img" "$OUT/probe.img"
PROBE_VOR=$(sha256sum < "$OUT/probe.img" | cut -d' ' -f1)
lauf "$OUT/probe.img" "dualcli /dev/hdb --quelle /dev/hda" "$OUT/ser-probe.txt"
tr -d '\000' < "$OUT/ser-probe.txt" 2>/dev/null | grep -a '^dual:' | head -12 | sed 's/^/        /'

grep -qa 'dual: table=2' "$OUT/ser-probe.txt" \
    && ok "it reads the foreign table: 2 partitions" \
    || bad "the foreign table was not read"
grep -qa "dual: part 1 $ESP_START $((ESP_START+ESP_SEK-1)) 1" "$OUT/ser-probe.txt" \
    && ok "Partition 1 richtig erkannt: Sektor $ESP_START..$((ESP_START+ESP_SEK-1)), Art EFI" \
    || bad "partition 1 was not read correctly"
grep -qa "dual: part 2 $DAT_START $((DAT_START+DAT_SEK-1)) 2" "$OUT/ser-probe.txt" \
    && ok "Partition 2 richtig erkannt: Sektor $DAT_START..$((DAT_START+DAT_SEK-1)), Art Daten" \
    || bad "partition 2 was not read correctly"
grep -qa "dual: free $((DAT_START+DAT_SEK))" "$OUT/ser-probe.txt" \
    && ok "the free area was found (from sector $((DAT_START+DAT_SEK)))" \
    || bad "the free area was not found"
grep -qa 'dual: esp=1' "$OUT/ser-probe.txt" \
    && ok "the existing EFI partition was found" \
    || bad "the existing EFI partition was not found"
grep -qa 'dual: dry run, ende' "$OUT/ser-probe.txt" \
    && ok "the dry run stops before the first write access" \
    || bad "the dry run did not finish cleanly"

PROBE_NACH=$(sha256sum < "$OUT/probe.img" | cut -d' ' -f1)
if [ "$PROBE_VOR" = "$PROBE_NACH" ]; then
    ok "WITHOUT --ja THE DISK IS UNCHANGED BYTE FOR BYTE"
else
    bad "the dry run wrote to the disk"
fi
rm -f "$OUT/probe.img"

# ==================================================================
titel "3. wirklich installieren -- in den freien Platz"
# ==================================================================
lauf "$OUT/platte.img" "dualcli /dev/hdb --quelle /dev/hda --ja --name hdb" "$OUT/ser.txt"
tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -a '^dual:' | head -20 | sed 's/^/        /'

grep -qa 'dual: new p3' "$OUT/ser.txt" \
    && ok "it added a new entry as partition 3" \
    || bad "no third partition entry was created"
grep -qa 'dual: copied' "$OUT/ser.txt" \
    && ok "the root was copied into the free area" \
    || bad "the root was not copied"
grep -qa 'dual: menu=2' "$OUT/ser.txt" \
    && ok "the boot menu was written with TWO entries" \
    || bad "the boot menu does not have two entries"
grep -qa 'dual: done' "$OUT/ser.txt" \
    && ok "the installation reports done" \
    || bad "the installation did not finish"

# ==================================================================
titel "4. DIE FREMDEN DATEN -- BYTEWEISE UNVERAENDERT?"
# ==================================================================
NACH_DAT=$(daten_summe "$OUT/platte.img")
echo "   BEFORE  data $VOR_DAT"
echo "   AFTER   data $NACH_DAT"
if [ "$VOR_DAT" = "$NACH_DAT" ]; then
    ok "THE FOREIGN DATA PARTITION IS UNCHANGED BYTE FOR BYTE"
else
    bad "the foreign data partition was changed"
fi

# ==================================================================
titel "5. die Dateien des fremden Systems in der ESP"
# ==================================================================
mdir -i "$OUT/platte.img@@$ESPOFF" ::/EFI/Microsoft/Boot > "$OUT/esp-fremd.txt" 2>&1
sed 's/^/        /' "$OUT/esp-fremd.txt" | head -10
grep -qi 'bootmgfw' "$OUT/esp-fremd.txt" \
    && ok "THE FOREIGN BOOT MANAGER (bootmgfw.efi) IS STILL THERE" \
    || bad "bootmgfw.efi ist verschwunden"
grep -qi 'BCD' "$OUT/esp-fremd.txt" \
    && ok "the foreign file BCD in the ESP is still there" \
    || bad "the foreign file BCD has disappeared"

mdir -i "$OUT/platte.img@@$ESPOFF" ::"/EFI/${MARKE_KURZ}" > "$OUT/esp-osum.txt" 2>&1
sed 's/^/        /' "$OUT/esp-osum.txt" | head -8
grep -qi 'osum' "$OUT/esp-osum.txt" \
    && ok "${MARKE_PRODUKT} lives in its own directory /EFI/${MARKE_KURZ}" \
    || bad "nothing is under /EFI/${MARKE_KURZ}"

# ==================================================================
titel "6. ist die GPT gueltig? -- mit FREMDEN Augen gelesen"
# ==================================================================
sgdisk -v "$OUT/platte.img" > "$OUT/gpt-pruef.txt" 2>&1
sgdisk -p "$OUT/platte.img" > "$OUT/gpt-nachher.txt" 2>&1
sed 's/^/        /' "$OUT/gpt-nachher.txt" | tail -7
grep -qi 'No problems found' "$OUT/gpt-pruef.txt" \
    && ok "sgdisk sagt: No problems found (beide Koepfe, beide CRC32)" \
    || { bad "sgdisk complains about the table:"; sed 's/^/          /' "$OUT/gpt-pruef.txt" | head -6; }
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
titel "7. bietet das Bootmenue beide Systeme an?"
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

# ==================================================================
titel "8. DIE GEGENPROBE: zu wenig freier Platz"
bash tools/dual/fremdplatte.sh "$OUT/eng.img" 80 > /dev/null 2>&1
sgdisk -d 2 "$OUT/eng.img" > /dev/null 2>&1
sgdisk -n "2:$DAT_START:163806" -t 2:0700 -c 2:"Basic data partition" "$OUT/eng.img" > /dev/null 2>&1
ENG_VOR=$(sha256sum < "$OUT/eng.img" | cut -d' ' -f1)
sgdisk -p "$OUT/eng.img" 2>&1 | tail -4 | sed 's/^/        /'

lauf "$OUT/eng.img" "dualcli /dev/hdb --source /dev/hda --ja --name hdb" "$OUT/ser-eng.txt"
tr -d '\000' < "$OUT/ser-eng.txt" 2>/dev/null | grep -a '^dual:' | head -8 | sed 's/^/        /'

if grep -qa 'dual: too little' "$OUT/ser-eng.txt"; then
    ok "it aborts with a clear message: not enough free space"
else
    bad "it did not report the missing space"
fi
grep -qa 'dual: done' "$OUT/ser-eng.txt" \
    && bad "it installed despite the missing space" \
    || ok "it did NOT install"

ENG_NACH=$(sha256sum < "$OUT/eng.img" | cut -d' ' -f1)
if [ "$ENG_VOR" = "$ENG_NACH" ]; then
    ok "THE DISK IS UNCHANGED BYTE FOR BYTE AFTER THE ABORT"
else
    bad "the disk was changed despite the abort"
fi
rm -f "$OUT/eng.img"

printf '\n=======================================================\n'
printf 'DUALBOOT OHNE FENSTER:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
