#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fremdfs/bild-explorer.sh -- DAS BILD: EIN FREMDES DATEISYSTEM
# IM DATEIMANAGER.
#
# Der Auftrag dieser Runde verlangt ein Bild vom Explorer mit dem
# fremden Dateisystem darin. Zahlen auf der seriellen Leitung sagen,
# dass die Oktette stimmen; ein Bild sagt, dass ein Mensch die Dateien
# wirklich SIEHT -- mit den richtigen Namen, den richtigen Groessen
# und den Umlauten an der richtigen Stelle.
#
# Der Weg ist der der Runde EXPLORER-2: `tools/design/capture.sh`
# fährt eine echte Maschine mit Fensterserver hoch und schickt ihr ein
# Drehbuch; die Bilder kommen aus QEMUs Monitor (`screendump`). Neu ist
# nur der Parameter `zweite=` -- die Platte mit dem fremden Dateisystem.
#
#   bash tools/fremdfs/bild-explorer.sh [ext4|ntfs] [bildverzeichnis]
#
# Die Bilder landen in docs/bilder/fremdfs-<art>-*.png.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

ART=${1:-ext4}
BILD=${2:-}

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

if [ -z "$BILD" ]; then
    BILD="$W/bild"
    echo ">> die Pruefbilder bauen ..."
    bash tools/fremdfs/bild.sh "$BILD" >"$W/bild.log" 2>&1 || {
        echo "die Abbilder lassen sich nicht bauen:"; tail -10 "$W/bild.log"
        exit 1; }
fi

case "$ART" in
    ext4) QUELLE="$BILD/ext4.img"; TYP=83 ;;
    ntfs) QUELLE="$BILD/ntfs.img"; TYP=7 ;;
    *) echo "usage: bild-explorer.sh [ext4|ntfs] [bildverzeichnis]"; exit 2 ;;
esac
[ -f "$QUELLE" ] || { echo "$QUELLE fehlt"; exit 1; }

# Die Partitionstafel drumherum -- wie im Pruefstand, damit das Bild
# dieselbe Lage zeigt wie die Messung.
groesse=$(stat -c %s "$QUELLE")
python3 - "$W/zweite.img" $(( groesse / 1048576 + 2 )) <<'PYEOF'
import sys
ziel, mib = sys.argv[1], int(sys.argv[2])
with open(ziel, 'wb') as f:
    f.seek(mib * 1048576 - 1)
    f.write(b'\0')
PYEOF
printf 'label: dos\nstart=2048, type=%s\n' "$TYP" \
    | sfdisk "$W/zweite.img" >/dev/null 2>&1
dd if="$QUELLE" of="$W/zweite.img" bs=512 seek=2048 conv=notrunc status=none

# DAS DREHBUCH.
#
# Der Laeufer faehrt mit `fs=an`, also MIT Wurzelplatte und VFS-Schicht
# (sonst gaebe es nichts einzuhaengen). Das fremde Dateisystem kommt
# ueber `script=` auf /mnt, BEVOR der Fensterserver den Dateimanager
# startet -- danach steht es schon da, und der Dateimanager muss nur
# noch hingeschickt werden.
cat > "$W/dreh.txt" <<'DREH'
warteauf explorer: modell n= || 120
warte 6
foto 1-start
# In die Pfadleiste tippen: Strg+L macht aus ihr ein Textfeld.
taste ctrl-l
warte 4
taste ctrl-a
warte 2
tippe /mnt
taste ret
warte 12
warte 8
foto 2-fremd
# Ein Unterverzeichnis: das mit den 512 Eintraegen.
taste ctrl-l
warte 3
taste ctrl-a
warte 2
tippe /mnt/viele
taste ret
warte 12
warte 8
foto 3-viele
# Und der tiefe Pfad.
taste ctrl-l
warte 3
taste ctrl-a
warte 2
tippe /mnt/a/b/c/d
taste ret
warte 12
warte 6
foto 4-tief
DREH

echo ">> die Maschine fahren (Art: $ART) ..."
bash tools/design/capture.sh "$W/lauf" res=1280x800 \
    extra="nostart wigapp=/bin/explorer script=mount /dev/hdb1 /mnt $ART -r" \
    fs=an \
    progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme mount umount" \
    zweite="$W/zweite.img" drehbuch="$W/dreh.txt" \
    > "$W/lauf.log" 2>&1

S="$W/lauf/serial.txt"
if [ ! -s "$S" ]; then
    echo "FEHLGESCHLAGEN: keine serielle Ausgabe"
    tail -20 "$W/lauf.log"
    exit 1
fi

echo ">> was die Maschine gemeldet hat:"
grep -aE "^(ext4|ntfs):" "$S" | head -4 | sed 's/^/    /'
grep -aE '^explorer: cd ' "$S" | head -5 | sed 's/^/    /'

# Die Bilder wandeln und ablegen.
mkdir -p docs/bilder
python3 - "$W/lauf" "$ART" <<'PY'
import glob, os, sys
from PIL import Image
quelle, art = sys.argv[1], sys.argv[2]
n = 0
for p in sorted(glob.glob(os.path.join(quelle, "*.ppm"))):
    name = os.path.basename(p)[:-4]
    ziel = os.path.join("docs", "bilder", f"fremdfs-{art}-{name}.png")
    Image.open(p).convert("RGB").save(ziel)
    print("   ", ziel)
    n += 1
print(f">> {n} Bilder")
PY

echo ">> Protokoll: $W/lauf.log (wird gleich aufgeraeumt)"
