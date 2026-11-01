#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

ART=${1:-ext4}
BILD=${2:-}

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

if [ -z "$BILD" ]; then
    BILD="$W/bild"
    echo ">> building the check images ..."
    bash tools/fremdfs/image.sh "$BILD" >"$W/bild.log" 2>&1 || {
        echo "the images cannot be built:"; tail -10 "$W/bild.log"
        exit 1; }
fi

case "$ART" in
    ext4) QUELLE="$BILD/ext4.img"; TYP=83 ;;
    ntfs) QUELLE="$BILD/ntfs.img"; TYP=7 ;;
    *) echo "usage: image-explorer.sh [ext4|ntfs] [bildverzeichnis]"; exit 2 ;;
esac
[ -f "$QUELLE" ] || { echo "$QUELLE fehlt"; exit 1; }

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

cat > "$W/dreh.txt" <<'DREH'
warteauf explorer: modell n= || 120
warte 6
foto 1-start
taste ctrl-l
warte 4
taste ctrl-a
warte 2
tippe /mnt
taste ret
warte 12
warte 8
foto 2-fremd
taste ctrl-l
warte 3
taste ctrl-a
warte 2
tippe /mnt/viele
taste ret
warte 12
warte 8
foto 3-viele
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
    echo "FAILED: no serial output"
    tail -20 "$W/lauf.log"
    exit 1
fi

echo ">> what the machine reported:"
grep -aE "^(ext4|ntfs):" "$S" | head -4 | sed 's/^/    /'
grep -aE '^explorer: cd ' "$S" | head -5 | sed 's/^/    /'

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

echo ">> log: $W/lauf.log (cleaned up shortly)"
