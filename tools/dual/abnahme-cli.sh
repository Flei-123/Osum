#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dual/abnahme-cli.sh -- DIE ABNAHME OHNE FENSTERSERVER.
#
#   bash tools/dual/abnahme-cli.sh [bauverzeichnis] [ausgabeverzeichnis]
#
# ==================================================================
# WARUM ES DIESEN LAUF ZUSAETZLICH ZUM FENSTER GIBT
# ==================================================================
#
# Die Zusage dieser Runde -- "OrientOS legt sich neben ein fremdes
# System, ohne dessen Daten anzufassen" -- ist eine Aussage ueber die
# PLATTE und nicht ueber die Oberflaeche. Sie muss auch dann pruefbar
# sein, wenn der Fensterserver nicht laeuft.
#
# Deshalb faehrt dieser Lauf denselben Weg ueber `/bin/dualcli`: dieselbe
# `dualkern.neben_schreiben`, dasselbe `instkern.wurzel_kopieren_ab`,
# dieselbe Startdatei -- nur ohne Fenster, gestartet mit `script=`.
#
# GEMESSEN WIRD GENAU DAS, WAS DER AUFTRAG VERLANGT:
#
#   * die fremden Partitionen sind BYTEWEISE unveraendert,
#   * die Datei in der ESP ist noch da,
#   * die GPT ist gueltig -- mit einem FREMDEN Werkzeug gegengelesen,
#   * das Bootmenue bietet beide Eintraege an,
#   * und die Gegenprobe: zu wenig Platz -> sauberer Abbruch, Platte
#     unveraendert.
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

# DIE LAGE DER FREMDEN PARTITIONEN WIRD GELESEN, NICHT GETIPPT.
# `fremdplatte.sh` darf seine Groessen aendern, ohne dass die
# Pruefsummen hier danebengreifen -- eine Summe ueber den falschen
# Bereich waere still gruen.
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

# Einen Lauf fahren. $1 = Plattendatei, $2 = Argumente fuer dualcli,
# $3 = Protokolldatei.
lauf() {
    local img=$1 arg=$2 ser=$3
    rm -f "$ser"
    # ============================ WARUM KEIN `-initrd` UND KEIN `modfs`
    #
    # GEMESSEN, nicht vermutet: mit `modfs` liegt die Wurzel als
    # Boot-Modul im Speicher, und darin steht `/etc/ziel` auf `grafik`.
    # `init` startet dann die Oberflaeche und `script=` kommt nie an --
    # auf der Leitung endet es bei "init: dienste=1".
    #
    # Also derselbe Aufbau wie in tools/k14/run.sh: die WURZEL ist eine
    # gewoehnliche Platte (hda), und die fremde Platte, um die es geht,
    # haengt als ZWEITE daran (hdb). Der Kern findet seine Wurzel auf
    # hda, `script=` laeuft, und `dualcli` bekommt /dev/hdb als Ziel --
    # das ist ausserdem naeher an der Wirklichkeit: ein Mensch
    # installiert von einem Medium auf eine ANDERE Platte.
    cp -f "$BAU/root.img" "$OUT/wurzel.img"
    # ============================ UND WARUM `/etc/ziel` UMGESCHRIEBEN WIRD
    #
    # Auch ohne `modfs` liest `init` seine Wurzel von der Platte, und
    # dort steht `/etc/ziel` auf `grafik`. Dann startet `kgui` die
    # Oberflaeche, und `script=` kommt nie an -- gemessen: die Leitung
    # endet bei "init: dienste=1", ohne eine einzige `dual:`-Zeile.
    #
    # Fuer DIESEN Lauf soll die Maschine in die Konsole starten. Also
    # wird in der KOPIE des Wurzelabbilds das Wort ausgetauscht --
    # `mkfs.py where` sagt, in welchem Block es liegt. Das ist eine
    # Aenderung am Messaufbau und keine am System: das ausgelieferte
    # Abbild bleibt `grafik`.
    local zblk
    zblk=$(python3 tools/osum/mkfs.py where "$OUT/wurzel.img" /etc/ziel 2>/dev/null \
        | sed -n 's/.*first=\([0-9]*\).*/\1/p')
    if [ -n "$zblk" ]; then
        # NICHT LAENGER ALS DAS ALTE WORT: die Laenge steht in der
        # Inode, und die wird hier nicht angefasst. "grafik\n" sind
        # sieben Oktette. `init` kennt das Wort "kons" nicht und faellt
        # dann ausdruecklich auf die Konsole zurueck (read_target:
        # target_of == 0 -> Z_KONSOLE) -- genau das ist gewollt.
        printf 'kons\n\0\0' | dd of="$OUT/wurzel.img" bs=512 seek="$zblk" \
            conv=notrunc status=none
    fi
    timeout "${LIMIT:-600}" $QEMU_X86 -m 512 \
        -kernel "$BAU/osum.mb" \
        -append "osum vfs nokbd nosched noproc noring3 script=$arg;exit" \
        -serial "file:$ser" -display none -no-reboot \
        -drive "file=$OUT/wurzel.img,format=raw,if=ide,index=0" \
        -drive "file=$img,format=raw,if=ide,index=1" \
        > "$OUT/qemu.log" 2>&1
    rm -f "$OUT/wurzel.img"
    return 0
}

# ==================================================================
titel "1. eine Platte, auf der schon jemand wohnt"
# ==================================================================
bash tools/dual/fremdplatte.sh "$OUT/platte.img" 80 | sed 's/^/   /'
lies_lage "$OUT/platte.img"
echo "   gemessen: ESP $ESP_START+$ESP_SEK, Daten $DAT_START+$DAT_SEK"
VOR_ESP=$(esp_summe   "$OUT/platte.img")
VOR_DAT=$(daten_summe "$OUT/platte.img")
echo "   VORHER  esp   $VOR_ESP"
echo "   VORHER  daten $VOR_DAT"

# ==================================================================
titel "2. der Probelauf -- versteht es die fremde Platte?"
# ==================================================================
# OHNE `--ja`: es darf KEIN Oktett geschrieben werden.
cp -f "$OUT/platte.img" "$OUT/probe.img"
PROBE_VOR=$(sha256sum < "$OUT/probe.img" | cut -d' ' -f1)
lauf "$OUT/probe.img" "dualcli /dev/hdb --quelle /dev/hda" "$OUT/ser-probe.txt"
tr -d '\000' < "$OUT/ser-probe.txt" 2>/dev/null | grep -a '^dual:' | head -12 | sed 's/^/        /'

grep -qa 'dual: tafel=2' "$OUT/ser-probe.txt" \
    && ok "es liest die fremde Tafel: 2 Partitionen" \
    || bad "die fremde Tafel wurde nicht gelesen"
# Die ESP ist Partition 1, Typ 1 (T_ESP); die Daten sind Typ 2.
grep -qa "dual: part 1 $ESP_START $((ESP_START+ESP_SEK-1)) 1" "$OUT/ser-probe.txt" \
    && ok "Partition 1 richtig erkannt: Sektor $ESP_START..$((ESP_START+ESP_SEK-1)), Art EFI" \
    || bad "Partition 1 wurde nicht richtig gelesen"
grep -qa "dual: part 2 $DAT_START $((DAT_START+DAT_SEK-1)) 2" "$OUT/ser-probe.txt" \
    && ok "Partition 2 richtig erkannt: Sektor $DAT_START..$((DAT_START+DAT_SEK-1)), Art Daten" \
    || bad "Partition 2 wurde nicht richtig gelesen"
grep -qa "dual: frei $((DAT_START+DAT_SEK))" "$OUT/ser-probe.txt" \
    && ok "der freie Bereich wurde gefunden (ab Sektor $((DAT_START+DAT_SEK)))" \
    || bad "der freie Bereich wurde nicht gefunden"
grep -qa 'dual: esp=1' "$OUT/ser-probe.txt" \
    && ok "die vorhandene EFI-Partition wurde gefunden" \
    || bad "die vorhandene EFI-Partition wurde nicht gefunden"
grep -qa 'dual: probelauf, ende' "$OUT/ser-probe.txt" \
    && ok "der Probelauf hoert vor dem ersten Schreibzugriff auf" \
    || bad "der Probelauf ist nicht sauber zu Ende gekommen"

PROBE_NACH=$(sha256sum < "$OUT/probe.img" | cut -d' ' -f1)
if [ "$PROBE_VOR" = "$PROBE_NACH" ]; then
    ok "OHNE --ja IST DIE PLATTE OKTETT FUER OKTETT UNVERAENDERT"
else
    bad "der Probelauf hat auf die Platte geschrieben"
fi
rm -f "$OUT/probe.img"

# ==================================================================
titel "3. wirklich installieren -- in den freien Platz"
# ==================================================================
lauf "$OUT/platte.img" "dualcli /dev/hdb --quelle /dev/hda --ja" "$OUT/ser.txt"
tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -a '^dual:' | head -20 | sed 's/^/        /'

grep -qa 'dual: neu p3' "$OUT/ser.txt" \
    && ok "es hat einen neuen Eintrag als Partition 3 ergaenzt" \
    || bad "es wurde kein dritter Partitionseintrag angelegt"
grep -qa 'dual: kopiert' "$OUT/ser.txt" \
    && ok "die Wurzel wurde in den freien Bereich kopiert" \
    || bad "die Wurzel wurde nicht kopiert"
grep -qa 'dual: menue=2' "$OUT/ser.txt" \
    && ok "das Bootmenue wurde mit ZWEI Eintraegen geschrieben" \
    || bad "das Bootmenue hat nicht zwei Eintraege"
grep -qa 'dual: fertig' "$OUT/ser.txt" \
    && ok "die Installation meldet sich fertig" \
    || bad "die Installation ist nicht fertig geworden"

# ==================================================================
titel "4. DIE FREMDEN DATEN -- BYTEWEISE UNVERAENDERT?"
# ==================================================================
NACH_DAT=$(daten_summe "$OUT/platte.img")
echo "   VORHER  daten $VOR_DAT"
echo "   NACHHER daten $NACH_DAT"
if [ "$VOR_DAT" = "$NACH_DAT" ]; then
    ok "DIE FREMDE DATENPARTITION IST OKTETT FUER OKTETT UNVERAENDERT"
else
    bad "die fremde Datenpartition wurde veraendert"
fi

# ==================================================================
titel "5. die Dateien des fremden Systems in der ESP"
# ==================================================================
mdir -i "$OUT/platte.img@@$ESPOFF" ::/EFI/Microsoft/Boot > "$OUT/esp-fremd.txt" 2>&1
sed 's/^/        /' "$OUT/esp-fremd.txt" | head -10
grep -qi 'bootmgfw' "$OUT/esp-fremd.txt" \
    && ok "DER FREMDE BOOTMANAGER (bootmgfw.efi) IST NOCH DA" \
    || bad "bootmgfw.efi ist verschwunden"
grep -qi 'BCD' "$OUT/esp-fremd.txt" \
    && ok "die fremde Datei BCD in der ESP ist noch da" \
    || bad "die fremde Datei BCD ist verschwunden"

mdir -i "$OUT/platte.img@@$ESPOFF" ::/EFI/orientos > "$OUT/esp-osum.txt" 2>&1
sed 's/^/        /' "$OUT/esp-osum.txt" | head -8
grep -qi 'osum' "$OUT/esp-osum.txt" \
    && ok "OrientOS liegt in seinem eigenen Verzeichnis /EFI/orientos" \
    || bad "unter /EFI/orientos liegt nichts"

# ==================================================================
titel "6. ist die GPT gueltig? -- mit FREMDEN Augen gelesen"
# ==================================================================
sgdisk -v "$OUT/platte.img" > "$OUT/gpt-pruef.txt" 2>&1
sgdisk -p "$OUT/platte.img" > "$OUT/gpt-nachher.txt" 2>&1
sed 's/^/        /' "$OUT/gpt-nachher.txt" | tail -7
grep -qi 'No problems found' "$OUT/gpt-pruef.txt" \
    && ok "sgdisk sagt: No problems found (beide Koepfe, beide CRC32)" \
    || { bad "sgdisk beanstandet die Tafel:"; sed 's/^/          /' "$OUT/gpt-pruef.txt" | head -6; }
n=$(grep -cE '^ +[0-9]+ +[0-9]+' "$OUT/gpt-nachher.txt" || true)
[ "${n:-0}" -ge 3 ] && ok "die Tafel traegt jetzt $n Partitionen (vorher 2)" \
    || bad "die Tafel traegt nur ${n:-0} Partitionen"
grep -qi 'OSUM' "$OUT/gpt-nachher.txt" \
    && ok "die neue Partition heisst OSUM" \
    || bad "keine Partition namens OSUM"

python3 tools/dual/tafelpruef.py "$OUT/platte.img" > "$OUT/tafelpruef.txt" 2>&1
TPRC=$?
sed 's/^/        /' "$OUT/tafelpruef.txt"
[ "$TPRC" = 0 ] && ok "der unabhaengige Pruefer bestaetigt beide Koepfe und beide Tafelsummen" \
    || bad "der unabhaengige Pruefer beanstandet die Tafel"

# ==================================================================
titel "7. bietet das Bootmenue beide Systeme an?"
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

# ==================================================================
titel "8. DIE GEGENPROBE: zu wenig freier Platz"
# ==================================================================
# Dieselbe Platte, aber ohne Luecke: die Datenpartition reicht bis ans
# Ende. Jetzt MUSS das Programm abbrechen, und die Platte muss
# unveraendert bleiben.
bash tools/dual/fremdplatte.sh "$OUT/eng.img" 80 > /dev/null 2>&1
# Die zweite Partition bis kurz vors Ende verlaengern -- mit sgdisk,
# also von aussen.
sgdisk -d 2 "$OUT/eng.img" > /dev/null 2>&1
sgdisk -n "2:$DAT_START:163806" -t 2:0700 -c 2:"Basic data partition" "$OUT/eng.img" > /dev/null 2>&1
ENG_VOR=$(sha256sum < "$OUT/eng.img" | cut -d' ' -f1)
sgdisk -p "$OUT/eng.img" 2>&1 | tail -4 | sed 's/^/        /'

lauf "$OUT/eng.img" "dualcli /dev/hdb --quelle /dev/hda --ja" "$OUT/ser-eng.txt"
tr -d '\000' < "$OUT/ser-eng.txt" 2>/dev/null | grep -a '^dual:' | head -8 | sed 's/^/        /'

if grep -qa 'dual: zu wenig' "$OUT/ser-eng.txt"; then
    ok "es bricht mit einer klaren Meldung ab: zu wenig freier Platz"
else
    bad "es hat den fehlenden Platz nicht gemeldet"
fi
grep -qa 'dual: fertig' "$OUT/ser-eng.txt" \
    && bad "es hat trotz fehlenden Platzes installiert" \
    || ok "es hat NICHT installiert"

ENG_NACH=$(sha256sum < "$OUT/eng.img" | cut -d' ' -f1)
if [ "$ENG_VOR" = "$ENG_NACH" ]; then
    ok "DIE PLATTE IST NACH DEM ABBRUCH OKTETT FUER OKTETT UNVERAENDERT"
else
    bad "die Platte wurde trotz Abbruch veraendert"
fi
rm -f "$OUT/eng.img"

printf '\n=======================================================\n'
printf 'DUALBOOT OHNE FENSTER:  %d gruen, %d rot\n' "$ok" "$bad"
printf '=======================================================\n'
[ "$bad" = 0 ] || exit 1
exit 0
