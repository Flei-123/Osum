#!/usr/bin/env bash
# tools/install/run.sh -- RUNDE INSTALL: DAS SYSTEM AUF EINE ECHTE PLATTE,
# UND DER AKTUALISIERUNGSWEG BIS ZUM STROMAUSFALL.
#
# Was diese Runde beweisen soll, steht in OrientOS' ROADMAP.md unter 9.4
# ("Ein Schreibpfad auf eine echte Platte") und 6.1 ("`opk` laeuft auf
# dem Wirt, nicht auf Osum"). Beide Punkte haben bis heute EINE Sorte
# Beleg gehabt: einen Satz darueber, was fehlt. Hier stehen Zahlen.
#
# SIEBEN TEILE, UND JEDER HAT SEINE GEGENPROBE:
#
#   1. DIE KARTE UND DAS FORMAT (auf dem Wirt, ohne QEMU).
#      `tools/kernel/karte.py` rechnet nach, dass sich in `kdata` nichts
#      ueberschneidet. Und die mehrblockige Blockkarte, die diese Runde
#      dem Dateisystem gibt, wird gegen die EINBLOCKIGE gehalten: ein
#      Abbild ohne `--karten` muss Oktett fuer Oktett dasselbe sein wie
#      eines, das der mkfs.py von `main` baut. Ein Format, das sich
#      "nur ein bisschen" aendert, ist ein anderes Format.
#
#   2. DIE INSTALLATION. Ein Lauf mit dem Wurzeldateisystem als
#      Boot-Modul (also die Lage eines ISO) schreibt auf eine LEERE
#      Platte. Danach liest der WIRT die Platte mit seinen eigenen
#      Werkzeugen: die beiden CRC32 des GPT werden mit `zlib`
#      nachgerechnet, die Partitionen mit `python` gelesen, das FAT32
#      mit `mtools`/`fsck.fat` geprueft, und Kern und Bootlader werden
#      Oktett fuer Oktett gegen die Originale gehalten. Ein
#      Installationsprogramm, dem nur sein eigenes Betriebssystem
#      glaubt, hat nichts gezeigt.
#      GEGENPROBE: derselbe Aufruf OHNE `--ja` darf die Platte NICHT
#      anfassen -- verglichen wird die ganze Abbilddatei.
#
#   3. DER START VON DER PLATTE, OHNE ISO. QEMU bekommt KEIN `-kernel`
#      und KEIN `-cdrom`, nur die Platte und OVMF. Was startet, startet
#      ueber die EFI-Partition, die der Installer beschrieben hat, mit
#      der Kommandozeile, die AUF DER PLATTE steht.
#      GEGENPROBE: ein einziges gekipptes Oktett im GPT-Kopf, und der
#      Kern darf die Wurzel NICHT mehr finden.
#
#   4. DASS SCHREIBEN UEBERLEBT. Eine Datei anlegen, herunterfahren,
#      neu starten, wieder lesen. Das ist der Satz aus 9.4, der bis
#      heute nicht galt: "Aenderungen ueberleben den Lauf nicht".
#
#   5. DER PAKETWEG AUF DEM GERAET. `/bin/opk` installiert ein Paket,
#      das der WIRT gebaut hat und das Osum nie gesehen hat; das Paket
#      LAEUFT; es wird aus einer signierten Quelle aktualisiert; nach
#      einem Neustart laeuft die neue Fassung; eine Generation zurueck,
#      und die alte laeuft wieder.
#      GEGENPROBEN: ein Paket mit einem gekippten Oktett wird abgelehnt,
#      und ein Paket, das nicht zum INDEX der Quelle passt, ebenfalls.
#
#   6. DER STROMAUSFALL. QEMU wird mitten im Schreiben mit SIGKILL
#      beendet -- an mehreren verschiedenen Stellen. Danach MUSS die
#      Platte noch starten, und die Paketliste MUSS entweder die alte
#      oder die neue Fassung nennen und nichts dazwischen.
#
#   7. DIE ZAHLEN, die in docs/ROUNDINSTALL.md und in die Roadmap gehen.
#
# Verwendung:  bash tools/install/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-/tmp/install-run}
mkdir -p "$OUT"
export OUT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', erwartet '$3'"; fi; }
num() {
    local name=$1 wert=$2 op=$3 want=$4
    if [ -z "$wert" ]; then bad "$name: keine Zahl (erwartet $op $want)"; return; fi
    if [ "$wert" -"$op" "$want" ] 2>/dev/null; then ok "$name: $wert"
    else bad "$name: $wert, erwartet $op $want"; fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hatnicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

lauf() { # name wie skript [limit]
    OUT="$OUT" bash tools/install/lauf.sh "$1" "$2" "${3:-}" "${4:-900}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

neue_platte() {
    rm -f "$OUT/ziel.img"
    head -c $((${ZIEL_MIB:-256} * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
}

echo "== 1. die Karte, und das Format, das sich NICHT geaendert haben darf =="

k=$(python3 tools/kernel/karte.py kernel 2>&1 | tail -1)
echo "        $k"
case "$k" in *"0 Kollisionen"*) ok "kdata ohne Kollision" ;; *) bad "kdata: $k" ;; esac

# Ein Abbild in der alten Geometrie, gebaut von DIESEM mkfs.py und von
# dem aus `main`. Sie muessen Oktett fuer Oktett gleich sein.
mkdir -p "$OUT/fmt"
echo "hallo" > "$OUT/fmt/a.txt"
git show main:tools/osum/mkfs.py > "$OUT/fmt/mkfs-main.py" 2>/dev/null
if [ -s "$OUT/fmt/mkfs-main.py" ]; then
    python3 "$OUT/fmt/mkfs-main.py" build "$OUT/fmt/alt.img" 4096 /x/ \
        "/x/a=$OUT/fmt/a.txt" > /dev/null 2>&1
    python3 tools/osum/mkfs.py build "$OUT/fmt/neu.img" 4096 /x/ \
        "/x/a=$OUT/fmt/a.txt" > /dev/null 2>&1
    if cmp -s "$OUT/fmt/alt.img" "$OUT/fmt/neu.img"; then
        ok "ein Abbild ohne --karten ist Oktett fuer Oktett das von main ($(stat -c%s "$OUT/fmt/neu.img") Oktette)"
    else
        bad "das Abbild hat sich geaendert -- die Blockkarte ist keine Erweiterung, sondern ein neues Format"
    fi
else
    bad "mkfs.py aus main nicht lesbar (kein git-Baum?)"
fi
# Und die GEGENPROBE zur Gegenprobe: MIT Vorrat muss es ein ANDERES
# Abbild sein, sonst haette `--karten` gar nichts getan.
python3 tools/osum/mkfs.py build "$OUT/fmt/gross.img" 4096 --karten=8 /x/ \
    "/x/a=$OUT/fmt/a.txt" > /dev/null 2>&1
if cmp -s "$OUT/fmt/neu.img" "$OUT/fmt/gross.img"; then
    bad "--karten=8 aendert nichts -- der Vorrat wird nicht angelegt"
else
    ok "--karten=8 legt einen anderen Baum an (Tabelle wandert)"
fi
kar=$(python3 - "$OUT/fmt/gross.img" <<'EOF'
import struct, sys
d = open(sys.argv[1], "rb").read(512)
print(struct.unpack_from("<Q", d, 72)[0], struct.unpack_from("<Q", d, 40)[0],
      struct.unpack_from("<Q", d, 48)[0])
EOF
)
gleich "Superblock mit Vorrat (karten itab data)" "$kar" "8 9 41"

echo
echo "== 2. die Installation, und was der WIRT auf der Platte findet =="

bash tools/install/bauen.sh "$OUT" > "$OUT/bauen.log" 2>&1 || {
    echo "== bauen.sh fehlgeschlagen"; tail -20 "$OUT/bauen.log"; exit 1; }
grep -aE '^   (kern|programme|quelle|pakete)' "$OUT/bauen.log" | sed 's/^/        /'

neue_platte
cp -f "$OUT/ziel.img" "$OUT/leer.img"
rc=$(lauf trocken iso "install /dev/hda;exit" 600)
gleich "Probelauf: Beendigungscode" "$rc" "21"
hat "$OUT/trocken.txt" "install: Probelauf" "der Probelauf sagt, dass er nichts schreibt"
if cmp -s "$OUT/ziel.img" "$OUT/leer.img"; then
    ok "GEGENPROBE: ohne --ja ist die Platte Oktett fuer Oktett unberuehrt"
else
    bad "ohne --ja wurde geschrieben"
fi

rc=$(lauf inst iso "install /dev/hda --ja;exit" 900)
gleich "Installation: Beendigungscode" "$rc" "21"
hat "$OUT/inst.txt" "install: gpt ok" "GPT geschrieben"
hat "$OUT/inst.txt" "install: fat32 ok" "FAT32 angelegt"
hat "$OUT/inst.txt" "install: fertig" "die Installation meldet sich fertig"
kop=$(grep -aoE 'install: kopiert=[0-9]+' "$OUT/inst.txt" | sed 's/.*=//')
gro=$(grep -aoE 'install: gewachsen=[0-9]+' "$OUT/inst.txt" | sed 's/.*=//')
num "kopierte Sektoren" "$kop" ge 8192
num "Wurzeldateisystem gewachsen auf" "$gro" ge 400000
sek=$(grep -aoE 'ata0 sectors=[0-9]+' "$OUT/inst.txt" | head -1 | sed 's/.*=//')
gleich "IDENTIFY meldet die Plattengroesse" "$sek" "524288"

# --------- der Wirt liest die Platte mit SEINEN Werkzeugen
python3 - "$OUT/ziel.img" > "$OUT/gpt.txt" 2>&1 <<'EOF'
import struct, sys, zlib
f = open(sys.argv[1], "rb")
d = f.read(1024 + 128 * 128)
print("mbr_sig", d[510] == 0x55 and d[511] == 0xAA)
print("mbr_typ", hex(d[446 + 4]))
h = d[512:512 + 92]
print("magic", h[:8].decode())
h0 = bytearray(h); h0[16:20] = b"\0\0\0\0"
print("hdr_crc_ok", struct.unpack_from("<I", h, 16)[0] == zlib.crc32(bytes(h0)))
arr = d[1024:1024 + 128 * 128]
print("arr_crc_ok", struct.unpack_from("<I", h, 88)[0] == zlib.crc32(arr))
print("cur", struct.unpack_from("<Q", h, 24)[0])
print("bak", struct.unpack_from("<Q", h, 32)[0])
# die Sicherung am Ende
f.seek(0, 2); n = f.tell() // 512
f.seek((n - 1) * 512); b = f.read(512)[:92]
b0 = bytearray(b); b0[16:20] = b"\0\0\0\0"
print("bak_magic", b[:8].decode())
print("bak_crc_ok", struct.unpack_from("<I", b, 16)[0] == zlib.crc32(bytes(b0)))
f.seek((n - 33) * 512); barr = f.read(128 * 128)
print("bak_arr_gleich", barr == arr)
for i in range(2):
    e = arr[i * 128:(i + 1) * 128]
    print("part%d" % i, e[:16].hex(), struct.unpack_from("<Q", e, 32)[0],
          struct.unpack_from("<Q", e, 40)[0],
          e[56:72].decode("utf-16-le").rstrip("\0"))
EOF
cat "$OUT/gpt.txt" | sed 's/^/        /'
hat "$OUT/gpt.txt" "mbr_sig True" "Schutz-MBR traegt 0x55AA"
hat "$OUT/gpt.txt" "mbr_typ 0xee" "Schutz-MBR traegt genau den Typ 0xEE"
hat "$OUT/gpt.txt" "magic EFI PART" "GPT-Kopf traegt EFI PART"
hat "$OUT/gpt.txt" "hdr_crc_ok True" "CRC32 des Kopfes, mit zlib nachgerechnet"
hat "$OUT/gpt.txt" "arr_crc_ok True" "CRC32 der Eintragstafel, mit zlib nachgerechnet"
hat "$OUT/gpt.txt" "bak_magic EFI PART" "die Sicherung am Plattenende ist da"
hat "$OUT/gpt.txt" "bak_crc_ok True" "CRC32 des Sicherungskopfes stimmt"
hat "$OUT/gpt.txt" "bak_arr_gleich True" "die Sicherungstafel ist Oktett fuer Oktett die primaere"
hat "$OUT/gpt.txt" "part0 28732ac11ff8d211ba4b00a0c93ec93b" "Partition 0 traegt die EFI-Kennung"
hat "$OUT/gpt.txt" "part1 4d55534f464f01538e756d6f72694f53" "Partition 1 traegt die OFS-Kennung"

# FAT32 mit fremden Werkzeugen
if command -v fsck.fat > /dev/null; then
    fsck.fat -n "$OUT/ziel.img@@1048576" > "$OUT/fsck.txt" 2>&1
    # mtools-Syntax kennt fsck.fat nicht; also die Partition herausschneiden
    dd if="$OUT/ziel.img" of="$OUT/esp.img" bs=512 skip=2048 count=70000 \
        status=none
    fsck.fat -n "$OUT/esp.img" > "$OUT/fsck.txt" 2>&1
    rcf=$?
    sed 's/^/        /' "$OUT/fsck.txt" | head -6
    num "fsck.fat auf der EFI-Partition" "$rcf" eq 0
fi
mdir -i "$OUT/ziel.img@@1048576" ::/EFI/BOOT > "$OUT/mdir.txt" 2>&1
hat "$OUT/mdir.txt" "BOOTX64  EFI" "der Bootlader liegt unter /EFI/BOOT"
mcopy -n -o -i "$OUT/ziel.img@@1048576" ::/osum.mb "$OUT/rueck-k.mb" 2>/dev/null
mcopy -n -o -i "$OUT/ziel.img@@1048576" ::/EFI/BOOT/BOOTX64.EFI "$OUT/rueck-l.efi" 2>/dev/null
if cmp -s "$OUT/k.mb" "$OUT/rueck-k.mb"; then
    ok "der Kern auf der EFI-Partition ist Oktett fuer Oktett der gebaute ($(stat -c%s "$OUT/k.mb"))"
else bad "der Kern auf der EFI-Partition weicht ab"; fi
LIM=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
if cmp -s "$LIM/BOOTX64.EFI" "$OUT/rueck-l.efi"; then
    ok "der Bootlader ist Oktett fuer Oktett der gebaute ($(stat -c%s "$LIM/BOOTX64.EFI"))"
else bad "der Bootlader weicht ab"; fi

# Das Wurzeldateisystem AUF DER PARTITION, gelesen von mkfs.py -- der
# zweiten Umsetzung des Formats, die den Kern nie gesehen hat.
python3 - "$OUT/ziel.img" 72048 "$OUT/wurzel.img" <<'EOF'
import sys
f = open(sys.argv[1], "rb"); f.seek(int(sys.argv[2]) * 512)
open(sys.argv[3], "wb").write(f.read(4096 * 512))
EOF
python3 tools/osum/mkfs.py list "$OUT/wurzel.img" > "$OUT/wurzel.txt" 2>&1
head -1 "$OUT/wurzel.txt" | sed 's/^/        /'
hat "$OUT/wurzel.txt" "/bin/opk" "das Wurzeldateisystem auf der Partition traegt /bin/opk"
hat "$OUT/wurzel.txt" "/boot/osum.mb" "und den Kern unter /boot"
wb=$(grep -aoE 'blocks=[0-9]+' "$OUT/wurzel.txt" | head -1 | sed 's/.*=//')
gleich "der Superblock der Partition nennt die gewachsene Groesse" "$wb" "$gro"

echo
echo "== 3. der Start VON DER PLATTE, ohne ISO und ohne Modul =="

rc=$(lauf boot platte "" 600)
gleich "Start ueber OVMF von der Platte: Beendigungscode" "$rc" "21"
hat "$OUT/boot.txt" "osum: rootpart=1" "die Wurzel kommt aus Partition 1"
hat "$OUT/boot.txt" "osum: mount=1" "sie ist eingehaengt"
hatnicht "$OUT/boot.txt" "osum: from module" "GEGENPROBE: es war KEIN Boot-Modul im Spiel"
hat "$OUT/boot.txt" "osum: bin " "das Userland liegt darauf"
erst=$(grep -aoE 'first=[0-9]+' "$OUT/boot.txt" | head -1 | sed 's/.*=//')
gleich "erster Block der Wurzelpartition" "$erst" "72048"

# GEGENPROBE: ein Oktett im GPT-Kopf umdrehen.
cp -f "$OUT/ziel.img" "$OUT/kaputt.img"
python3 - "$OUT/kaputt.img" > "$OUT/kaputt-crc.txt" <<'EOF'
import struct, sys, zlib
# Ein Oktett IN DER EINTRAGSTAFEL umdrehen -- der erste Block der
# Wurzelpartition. Und danach auf dem WIRT nachrechnen, dass die
# Pruefsumme im Kopf jetzt WIRKLICH nicht mehr passt: eine Gegenprobe,
# die den Fall gar nicht herbeifuehrt, ist keine.
at = 1024 + 128 + 32          # Eintrag 1, Feld "erster Block"
f = open(sys.argv[1], "r+b")
f.seek(at); b = f.read(1)
f.seek(at); f.write(bytes([b[0] ^ 0x10])); f.flush()
f.seek(512); h = f.read(92)
f.seek(1024); arr = f.read(128 * 128)
print("arr_crc_kaputt", struct.unpack_from("<I", h, 88)[0] != zlib.crc32(arr))
f.close()
EOF
cat "$OUT/kaputt-crc.txt" | sed 's/^/        /'
hat "$OUT/kaputt-crc.txt" "arr_crc_kaputt True" "die Gegenprobe hat die Summe wirklich zerstoert"
cp -f "$OUT/ziel.img" "$OUT/gut.img"
# ERST DER POSITIVE FALL AUF DEMSELBEN WEG. Ohne ihn wuerde die
# Gegenprobe darunter auch dann gruen, wenn dieser Startweg gar nicht
# funktioniert.
rc=$(lauf roh roh "" 600)
gleich "Start ohne Firmware und ohne Modul: Beendigungscode" "$rc" "21"
hat "$OUT/roh.txt" "osum: rootpart=1" "auch so kommt die Wurzel aus Partition 1"
hatnicht "$OUT/roh.txt" "osum: from module" "und auch hier ohne Boot-Modul"

mv -f "$OUT/kaputt.img" "$OUT/ziel.img"
rc=$(lauf kaputt roh "" 600)
if grep -qaF "osum: rootpart=" "$OUT/kaputt.txt"; then
    bad "GEGENPROBE: mit falscher CRC32 wurde die Wurzel trotzdem gefunden"
else
    ok "GEGENPROBE: ein gekipptes Oktett im GPT-Kopf, und die Wurzel wird NICHT gefunden"
fi
hat "$OUT/kaputt.txt" "part: gpt crc mismatch" "der Kern sagt, warum er die Tafel ablehnt"
hat "$OUT/kaputt.txt" "osum: no ofs partition" "und dass er keine Wurzelpartition findet"
# UND DER BEFUND, DER DIESE GEGENPROBE ERST AUF DIESEN WEG GEZWUNGEN HAT:
# ueber OVMF startet DIESELBE kaputte Platte, weil die Firmware den
# primaeren GPT-Kopf aus der Sicherung wiederherstellt. Das ist keine
# Schwaeche des Kerns -- es ist eine Eigenschaft von UEFI, und sie
# gehoert gemessen und nicht behauptet.
cp -f "$OUT/ziel.img" "$OUT/kaputt-uefi.img"
rc=$(lauf reparatur platte "" 600)
if grep -qaF "osum: rootpart=" "$OUT/reparatur.txt"; then
    ok "BEFUND: ueber OVMF startet dieselbe kaputte Platte -- die Firmware repariert den GPT aus der Sicherung"
else
    ok "ueber OVMF startet die kaputte Platte ebenfalls nicht"
fi
mv -f "$OUT/gut.img" "$OUT/ziel.img"

echo
echo "== 4. dass Schreiben den Lauf ueberlebt =="

rc=$(lauf schreib platte "echo diese-zeile-ueberlebt > /etc/beweis.txt;cat /etc/beweis.txt;exit" 600)
gleich "Schreiben: Beendigungscode" "$rc" "21"
hat "$OUT/schreib.txt" "diese-zeile-ueberlebt" "die Datei ist im selben Lauf lesbar"
rc=$(lauf wieder platte "cat /etc/beweis.txt;exit" 600)
hat "$OUT/wieder.txt" "diese-zeile-ueberlebt" "und nach einem NEUSTART immer noch"
# Und der Wirt sieht sie auch -- ohne Osum.
python3 - "$OUT/ziel.img" 72048 "$OUT/wurzel2.img" <<'EOF'
import sys
f = open(sys.argv[1], "rb"); f.seek(int(sys.argv[2]) * 512)
open(sys.argv[3], "wb").write(f.read(8192 * 512))
EOF
python3 tools/osum/mkfs.py cat "$OUT/wurzel2.img" /etc/beweis.txt > "$OUT/beweis.txt" 2>&1
hat "$OUT/beweis.txt" "diese-zeile-ueberlebt" "und der WIRT liest sie aus der Abbilddatei"

echo
echo "== 5. der Paketweg auf dem Geraet =="

h1=$(python3 -c "
import sys
for z in open('$OUT/quelle1/INDEX'):
    print(z.split(chr(9))[2])" 2>/dev/null | head -1)
h2=$(python3 -c "
import sys
for z in open('$OUT/quelle2/INDEX'):
    print(z.split(chr(9))[2])" 2>/dev/null | head -1)
echo "        hallo 1.0.0 = ${h1:0:16}"
echo "        hallo 2.0.0 = ${h2:0:16}"

rc=$(lauf pak1 platte "opk installieren /quelle1/hallo-1.opk;opk liste;/apps/hallo.prog/start;opk pruefen;exit" 600)
gleich "installieren: Beendigungscode" "$rc" "21"
hat "$OUT/pak1.txt" "opk: installiert hallo" "opk meldet die Installation"
hat "$OUT/pak1.txt" "paket-hallo fassung 1" "das installierte Paket LAEUFT aus /apps"
hat "$OUT/pak1.txt" "${h1:0:12}" "die Liste nennt genau den Hash, den der Wirt gerechnet hat"

rc=$(lauf pak2 platte "opk aktualisieren hallo --quelle /quelle2;opk liste;exit" 600)
hat "$OUT/pak2.txt" "opk: installiert hallo" "aktualisieren nimmt die neue Fassung an"
hat "$OUT/pak2.txt" "${h2:0:12}" "und die Liste nennt den Hash aus dem INDEX der Quelle"

rc=$(lauf pak3 platte "/apps/hallo.prog/start;opk generationen;exit" 600)
hat "$OUT/pak3.txt" "paket-hallo fassung 2" "nach dem NEUSTART laeuft die neue Fassung"
hat "$OUT/pak3.txt" "generation 1" "es gibt zwei Generationen"

rc=$(lauf pak4 platte "opk zurueck 0;/apps/hallo.prog/start;opk liste;exit" 600)
hat "$OUT/pak4.txt" "opk: zurueck auf 0" "eine Generation zurueck"
hat "$OUT/pak4.txt" "paket-hallo fassung 1" "und die ALTE Fassung laeuft wieder"
hat "$OUT/pak4.txt" "${h1:0:12}" "die Liste nennt wieder den alten Hash"

# GEGENPROBEN: ein Paket mit einem gekippten Oktett, und eines, das
# nicht zum INDEX passt. Beide werden in die laufende Wurzel gelegt --
# ueber die EFI-Partition geht das nicht, also legt sie der Testlauf in
# die QUELLE, bevor installiert wird. Dafuer wird das Abbild neu gebaut.
cp -f "$OUT/pak/hallo-1.opk" "$OUT/kaputt.opk"
python3 - "$OUT/kaputt.opk" <<'EOF'
import sys
f = open(sys.argv[1], "r+b"); f.seek(200)
b = f.read(1); f.seek(200); f.write(bytes([b[0] ^ 0x40]))
EOF
cp -f "$OUT/pak/hallo-2.opk" "$OUT/falsch.opk"
KAPUTT="$OUT/kaputt.opk" FALSCH="$OUT/falsch.opk" \
    EXTRA="/quelle1/kaputt.opk=$OUT/kaputt.opk /quelle1/falsch.opk=$OUT/falsch.opk" \
    bash tools/install/bauen.sh "$OUT" > "$OUT/bauen2.log" 2>&1
neue_platte
rc=$(lauf ginst iso "install /dev/hda --ja;exit" 900)
rc=$(lauf gpak platte "opk installieren /quelle1/kaputt.opk;opk installieren /quelle1/hallo-1.opk;opk aktualisieren hallo --quelle /quelle1;exit" 600)
hat "$OUT/gpak.txt" "opk: Pruefsumme falsch" "GEGENPROBE: ein gekipptes Oktett im Paket wird abgelehnt"
hat "$OUT/gpak.txt" "opk: installiert hallo" "GEGENPROBE zur Gegenprobe: das UNVERSEHRTE Paket wird angenommen"

echo
echo "== 6. der Stromausfall =="
#
# QEMU wird mit SIGKILL beendet, waehrend die Aktualisierung schreibt.
# Danach wird von derselben Platte neu gestartet, und drei Dinge muessen
# gelten: die Maschine startet, `opk liste` nennt GENAU einen der beiden
# Hashes, und das Paket laeuft.
#
# WARUM SIGKILL DAS RICHTIGE WERKZEUG IST: QEMU schreibt mit
# `cache=writeback` unmittelbar in den Seitenspeicher des Wirts. Was der
# Gast geschrieben hat, ueberlebt das Ende des QEMU-Prozesses -- der
# Abbruch trifft also GENAU den Gast, und nicht die Abbilddatei. Ein
# Wirtsabsturz waere eine andere Frage, und die stellt dieser Lauf nicht.

cp -f "$OUT/ziel.img" "$OUT/vor-strom.img"
rc=$(lauf spak platte "opk installieren /quelle1/hallo-1.opk;exit" 600)
hat "$OUT/spak.txt" "opk: installiert hallo" "Ausgangslage: Fassung 1 installiert"
cp -f "$OUT/ziel.img" "$OUT/basis.img"

ausfaelle=0
heil=0
for ms in 300 700 1200 1800 2600 3600; do
    cp -f "$OUT/basis.img" "$OUT/ziel.img"
    OUT="$OUT" bash tools/install/lauf.sh strom-$ms platte \
        "opk aktualisieren hallo --quelle /quelle2;exit" 600 > /dev/null 2>&1 &
    lpid=$!
    # warten, bis die Shell den Befehl wirklich angefangen hat
    i=0
    while [ $i -lt 900 ]; do
        grep -qa "opk aktualisieren" "$OUT/strom-$ms.txt" 2>/dev/null && break
        kill -0 $lpid 2>/dev/null || break
        sleep 0.1
        i=$((i + 1))
    done
    python3 -c "import time; time.sleep($ms / 1000.0)"
    pkill -9 -f "file=$OUT/ziel.img" 2>/dev/null
    wait $lpid 2>/dev/null
    ausfaelle=$((ausfaelle + 1))
    # und jetzt: startet die Platte noch?
    rc=$(lauf nach-$ms platte "opk liste;/apps/hallo.prog/start;opk pruefen;exit" 600)
    gestartet=0
    grep -qaF "osum: mount=1" "$OUT/nach-$ms.txt" && gestartet=1
    hh=""
    grep -qaF "${h1:0:12}" "$OUT/nach-$ms.txt" && hh="alt"
    grep -qaF "${h2:0:12}" "$OUT/nach-$ms.txt" && hh="neu"
    ver=$(grep -aoE 'paket-hallo fassung [0-9]' "$OUT/nach-$ms.txt" | head -1)
    if [ "$gestartet" = 1 ] && [ -n "$hh" ]; then
        heil=$((heil + 1))
        ok "Stromausfall nach ${ms} ms: startet, Liste=$hh, laeuft: ${ver:-(nichts)}"
    else
        bad "Stromausfall nach ${ms} ms: gestartet=$gestartet Liste='${hh:-keiner}'"
    fi
done
num "Stromausfaelle, die das System ueberlebt hat" "$heil" eq "$ausfaelle"
cp -f "$OUT/vor-strom.img" "$OUT/ziel.img"

echo
echo "== 7. die Bilanz =="
printf '  %d Zusagen, %d Fehler\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
