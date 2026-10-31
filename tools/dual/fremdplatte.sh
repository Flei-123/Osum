#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
#
#   bash tools/dual/fremdplatte.sh <ausgabe.img> [groesse_mib]
#
set -uo pipefail
cd "$(dirname "$0")/../.."

IMG=${1:?ausgabe.img fehlt}
MIB=${2:-80}

#     const DISK2_BLOCKS: u64 = 163840
#
ESP_MIB=${ESP_MIB:-34}
DATEN_MIB=${DATEN_MIB:-10}

# Sektoren (512 Oktette)
ESP_START=2048
ESP_SEK=$((ESP_MIB * 2048))
ESP_ENDE=$((ESP_START + ESP_SEK - 1))
DATEN_START=$((ESP_ENDE + 1))
DATEN_SEK=$((DATEN_MIB * 2048))
DATEN_ENDE=$((DATEN_START + DATEN_SEK - 1))

echo "== eine Platte, auf der schon jemand wohnt: $IMG ($MIB MiB)"

rm -f "$IMG"
dd if=/dev/zero of="$IMG" bs=1M count=0 seek="$MIB" status=none

# ---------------------------------------------------------- die Tafel
#
sgdisk -o "$IMG" > /dev/null 2>&1 || { echo "sgdisk -o fehlgeschlagen" >&2; exit 1; }
sgdisk -n "1:$ESP_START:$ESP_ENDE" -t 1:EF00 -c 1:"EFI System Partition" "$IMG" > /dev/null 2>&1 \
    || { echo "sgdisk ESP fehlgeschlagen" >&2; exit 1; }
sgdisk -n "2:$DATEN_START:$DATEN_ENDE" -t 2:0700 -c 2:"Basic data partition" "$IMG" > /dev/null 2>&1 \
    || { echo "sgdisk Daten fehlgeschlagen" >&2; exit 1; }

# ------------------------------------------------------- die ESP fuellen
ESPTMP=$(mktemp /tmp/fremd-esp-XXXXXX.img)
dd if=/dev/zero of="$ESPTMP" bs=1M count="$ESP_MIB" status=none
mkfs.vfat -F 32 -n "SYSTEM" "$ESPTMP" > /dev/null 2>&1 \
    || { echo "mkfs.vfat ESP fehlgeschlagen" >&2; exit 1; }

mmd -i "$ESPTMP" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot > /dev/null 2>&1

BEWEIS="tools/dual/beweis.efi"
if [ -f "$BEWEIS" ]; then
    mcopy -o -i "$ESPTMP" "$BEWEIS" ::/EFI/Microsoft/Boot/bootmgfw.efi \
        || { echo "mcopy bootmgfw fehlgeschlagen" >&2; exit 1; }
    echo "   bootmgfw.efi  echte UEFI-Anwendung ($(stat -c%s "$BEWEIS") Oktette)"
else
    printf 'FREMDER BOOTMANAGER -- PLATZHALTER\n' > /tmp/fremd-bm.bin
    mcopy -o -i "$ESPTMP" /tmp/fremd-bm.bin ::/EFI/Microsoft/Boot/bootmgfw.efi
    rm -f /tmp/fremd-bm.bin
    echo "   bootmgfw.efi  Platzhalter (beweis.efi fehlt)"
fi

printf 'Diese Datei gehoert dem fremden System. Sie muss die Installation ueberleben.\n' \
    > /tmp/fremd-marke.txt
mcopy -o -i "$ESPTMP" /tmp/fremd-marke.txt ::/EFI/Microsoft/Boot/BCD
rm -f /tmp/fremd-marke.txt

dd if="$ESPTMP" of="$IMG" bs=512 seek="$ESP_START" conv=notrunc status=none
rm -f "$ESPTMP"

# --------------------------------------------------- die Datenpartition
DATTMP=$(mktemp /tmp/fremd-dat-XXXXXX.img)
dd if=/dev/zero of="$DATTMP" bs=1M count="$DATEN_MIB" status=none
mkfs.vfat -F 16 -n "DATEN" "$DATTMP" > /dev/null 2>&1 \
    || { echo "mkfs.vfat Daten fehlgeschlagen" >&2; exit 1; }
printf 'Die Daten des fremden Systems. Kein Oktett darf sich aendern.\n' > /tmp/fremd-daten.txt
mcopy -o -i "$DATTMP" /tmp/fremd-daten.txt ::/WICHTIG.TXT
rm -f /tmp/fremd-daten.txt
dd if="$DATTMP" of="$IMG" bs=512 seek="$DATEN_START" conv=notrunc status=none
rm -f "$DATTMP"

# ------------------------------------------------------- die Pruefsummen
#
SUMMEN="${IMG%.img}.summen"
{
    printf 'esp   %s\n'   "$(dd if="$IMG" bs=512 skip="$ESP_START"   count="$ESP_SEK"   status=none | sha256sum | cut -d' ' -f1)"
    printf 'daten %s\n'   "$(dd if="$IMG" bs=512 skip="$DATEN_START" count="$DATEN_SEK" status=none | sha256sum | cut -d' ' -f1)"
} > "$SUMMEN"

FREI_START=$((DATEN_ENDE + 1))
FREI_ENDE=$((MIB * 2048 - 34))
FREI_MIB=$(( (FREI_ENDE - FREI_START + 1) / 2048 ))

echo "   ESP       Sektor $ESP_START..$ESP_ENDE   ($ESP_MIB MiB)"
echo "   Daten     Sektor $DATEN_START..$DATEN_ENDE   ($DATEN_MIB MiB)"
echo "   FREI      Sektor $FREI_START..$FREI_ENDE   ($FREI_MIB MiB)  <- hier soll ${MARKE_PRODUKT} hin"
echo "   Summen    $SUMMEN"
sed 's/^/     /' "$SUMMEN"
exit 0
