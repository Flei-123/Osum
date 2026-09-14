#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dual/fremdplatte.sh -- EINE PLATTE, AUF DER SCHON JEMAND WOHNT.
#
#   bash tools/dual/fremdplatte.sh <ausgabe.img> [groesse_mib]
#
# ==================================================================
# WOFUER DIESE DATEI DA IST
# ==================================================================
#
# Die Runde DUALBOOT verspricht, dass OrientOS sich NEBEN ein fremdes
# System legt, ohne es anzufassen. Dieses Versprechen laesst sich nur
# gegen eine Platte messen, auf der wirklich ein fremdes System liegt --
# und zwar eines, das man VORHER und NACHHER Oktett fuer Oktett
# vergleichen kann.
#
# Also wird hier genau das gebaut, was auf einem Rechner mit Windows
# steht, und keine Kulisse:
#
#   Partition 1   EFI-Systempartition (EF00), FAT32, 64 MiB.
#                 Darin liegt \EFI\Microsoft\Boot\bootmgfw.efi -- die
#                 Datei, die auf einem echten Rechner Windows startet.
#                 Hier ist es eine winzige, ECHTE UEFI-Anwendung
#                 (tools/dual/beweis.c), die sich auf der seriellen
#                 Leitung meldet. Eine Attrappe aus Nullen wuerde beim
#                 Kettenstart nichts sagen, und dann waere nicht zu
#                 unterscheiden, ob der Kettenstart lief oder nicht.
#
#   Partition 2   eine grosse Datenpartition (0700, "Microsoft basic
#                 data"), FAT32, mit einer Datei darin, deren Inhalt
#                 bekannt ist.
#
#   DAHINTER      FREIER PLATZ. Das ist die Stelle, in die OrientOS
#                 hineininstallieren soll -- und der Grund, warum diese
#                 Platte groesser ist als die beiden Partitionen
#                 zusammen.
#
# DIE PRUEFSUMMEN sind der eigentliche Zweck. `--summen` schreibt je
# Partition eine sha256 in eine Datei daneben; nach der Installation
# wird dieselbe Rechnung noch einmal gemacht und verglichen. Eine
# Partition, die sich um ein Oktett geaendert hat, faellt damit auf --
# auch dann, wenn alles andere gruen aussieht.
set -uo pipefail
cd "$(dirname "$0")/../.."

IMG=${1:?ausgabe.img fehlt}
MIB=${2:-512}

ESP_MIB=64
DATEN_MIB=128

# Sektoren (512 Oktette)
ESP_START=2048
ESP_SEK=$((ESP_MIB * 2048))
ESP_ENDE=$((ESP_START + ESP_SEK - 1))
DATEN_START=$((ESP_ENDE + 1))
DATEN_SEK=$((DATEN_MIB * 2048))
DATEN_ENDE=$((DATEN_START + DATEN_SEK - 1))

echo "== eine Platte, auf der schon jemand wohnt: $IMG ($MIB MiB)"

rm -f "$IMG"
# SPARSAM ANLEGEN. `dd seek=` ohne `count` schreibt kein einziges Oktett
# und legt nur die Groesse fest -- die Datei hat Loecher und belegt am
# Anfang nichts. Fuer QEMU ist das eine ganz gewoehnliche Platte; auf
# dem Wirt kostet ein Lauf dadurch Megabytes statt eines halben
# Gigabytes. Bei fuenf Auftraegen auf derselben Platte ist das der
# Unterschied zwischen "laeuft" und "kein Platz mehr".
dd if=/dev/zero of="$IMG" bs=1M count=0 seek="$MIB" status=none

# ---------------------------------------------------------- die Tafel
#
# Mit `sgdisk`, also einem FREMDEN Werkzeug. Das ist Absicht: die Tafel,
# die OrientOS gleich ergaenzen soll, darf nicht von OrientOS selbst
# stammen -- sonst misst der Lauf, ob das Programm seine eigene
# Schreibweise wiederfindet, und nicht, ob es eine fremde Tafel versteht.
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

# Der fremde Bootmanager. Wenn die gebaute UEFI-Anwendung danebenliegt,
# wird sie genommen; sonst eine Ersatzdatei mit bekanntem Inhalt.
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

# EINE DATEI, DIE NACHHER NOCH DA SEIN MUSS. Sie ist der Beleg dafuer,
# dass die ESP MITBENUTZT und nicht neu geschrieben wurde.
printf 'Diese Datei gehoert dem fremden System. Sie muss die Installation ueberleben.\n' \
    > /tmp/fremd-marke.txt
mcopy -o -i "$ESPTMP" /tmp/fremd-marke.txt ::/EFI/Microsoft/Boot/BCD
rm -f /tmp/fremd-marke.txt

dd if="$ESPTMP" of="$IMG" bs=512 seek="$ESP_START" conv=notrunc status=none
rm -f "$ESPTMP"

# --------------------------------------------------- die Datenpartition
DATTMP=$(mktemp /tmp/fremd-dat-XXXXXX.img)
dd if=/dev/zero of="$DATTMP" bs=1M count="$DATEN_MIB" status=none
mkfs.vfat -F 32 -n "DATEN" "$DATTMP" > /dev/null 2>&1 \
    || { echo "mkfs.vfat Daten fehlgeschlagen" >&2; exit 1; }
printf 'Die Daten des fremden Systems. Kein Oktett darf sich aendern.\n' > /tmp/fremd-daten.txt
mcopy -o -i "$DATTMP" /tmp/fremd-daten.txt ::/WICHTIG.TXT
rm -f /tmp/fremd-daten.txt
dd if="$DATTMP" of="$IMG" bs=512 seek="$DATEN_START" conv=notrunc status=none
rm -f "$DATTMP"

# ------------------------------------------------------- die Pruefsummen
#
# JE PARTITION EINE. Eine Summe ueber die ganze Platte waere hier
# nutzlos: die GPT AENDERT sich absichtlich (ein Eintrag kommt dazu),
# also waere die Gesamtsumme immer verschieden und sagte nichts darueber,
# ob die fremden DATEN heil sind.
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
echo "   FREI      Sektor $FREI_START..$FREI_ENDE   ($FREI_MIB MiB)  <- hier soll OrientOS hin"
echo "   Summen    $SUMMEN"
sed 's/^/     /' "$SUMMEN"
exit 0
