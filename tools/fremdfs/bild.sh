#!/usr/bin/env bash
#
#   bash tools/fremdfs/bild.sh <ausgabeverzeichnis>
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

AUS=${1:?usage: bild.sh <ausgabeverzeichnis>}
mkdir -p "$AUS"
AUS=$(cd "$AUS" && pwd)

for w in mkfs.ext4 debugfs mkntfs sha256sum gcc; do
    command -v "$w" >/dev/null 2>&1 || { echo "bild.sh: $w fehlt"; exit 2; }
done

leer_anlegen() { # datei mebioktette
    rm -f "$1"
    python3 - "$1" "$2" <<'PYEOF'
import sys
ziel, mib = sys.argv[1], int(sys.argv[2])
with open(ziel, 'wb') as f:
    f.seek(mib * 1048576 - 1)
    f.write(b'\0')
PYEOF
}

BAUM=$(mktemp -d)
HILF=$(mktemp -d)
trap 'rm -rf "$BAUM" "$HILF"' EXIT

if ! gcc -O2 -o "$HILF/ntfsbaum" tools/fremdfs/ntfsbaum.c -lntfs-3g 2>"$HILF/gcc.log"; then
    echo "bild.sh: ntfsbaum.c laesst sich nicht uebersetzen (ntfs-3g-dev fehlt?)"
    sed 's/^/    /' "$HILF/gcc.log" | head -10
    exit 2
fi

# ------------------------------------------------------------ der Baum
#
echo "bild: den Baum bauen ..."
printf 'hallo aus dem Gast\n' > "$BAUM/hallo.txt"
: > "$BAUM/leer.bin"
python3 - "$BAUM/mittel.bin" 204800 <<'PYEOF'
import sys
ziel, n = sys.argv[1], int(sys.argv[2])
with open(ziel, 'wb') as f:
    i, geschrieben = 0, 0
    while geschrieben < n:
        s = b'%d\n' % i
        f.write(s[:n - geschrieben])
        geschrieben += len(s[:n - geschrieben])
        i += 1
PYEOF
python3 - "$BAUM/gross.bin" 6291456 <<'PYEOF'
import sys
ziel, n = sys.argv[1], int(sys.argv[2])
with open(ziel, 'wb') as f:
    i, geschrieben = 0, 0
    while geschrieben < n:
        s = b'%d\n' % i
        f.write(s[:n - geschrieben])
        geschrieben += len(s[:n - geschrieben])
        i += 1
PYEOF
mkdir -p "$BAUM/a/b/c/d"
printf 'vier ebenen tief\n' > "$BAUM/a/b/c/d/tief.txt"
printf 'zwischenstufe\n' > "$BAUM/a/b/zwischen.txt"
printf 'mit umlauten im namen\n' > "$BAUM/umlaut-äöü.txt"
mkdir -p "$BAUM/viele"
for i in $(seq -w 0 511); do
    printf 'eintrag %s\n' "$i" > "$BAUM/viele/datei-$i"
done

VERWEIS_KURZ='hallo.txt'
VERWEIS_LANG="a/b/c/d/$(printf 'x%.0s' $(seq 1 90))"

( cd "$BAUM" && find . -type f -print0 | sort -z \
    | xargs -0 sha256sum | sed 's| \./| |' ) > "$AUS/baum.sha"

( cd "$BAUM" && find . -type d -print0 | sort -z | while IFS= read -r -d '' p; do
    n=$(find "$p" -mindepth 1 -maxdepth 1 | wc -l)
    printf '%s %s\n' "${p#./}" "$n"
  done ) > "$AUS/baum.liste"

printf '%s\n' "$VERWEIS_KURZ" > "$AUS/verweis-kurz.txt"
printf '%s\n' "$VERWEIS_LANG" > "$AUS/verweis-lang.txt"

# ---------------------------------------------------------------- ext4
#
ext4_befehle() { # quellverzeichnis
    local q=$1
    local rel
    ( cd "$q" && find . -mindepth 1 -type d | sort ) | while read -r rel; do
        printf 'mkdir %s\n' "${rel#./}"
    done
    ( cd "$q" && find . -mindepth 1 -type f | sort ) | while read -r rel; do
        printf 'write %s/%s %s\n' "$q" "${rel#./}" "${rel#./}"
    done
}

ext4_bauen() { # datei blockgroesse mibs journal(0/1)
    local img=$1 bs=$2 mib=$3 jrnl=$4
    rm -f "$img"
    leer_anlegen "$img" "$mib"
    local opts='extent,dir_index,^has_journal'
    [ "$jrnl" = 1 ] && opts='extent,dir_index,has_journal'
    mkfs.ext4 -q -F -b "$bs" -O "$opts" -E root_owner=0:0 -I 256 \
        "$img" >/dev/null 2>&1 || return 1

    dd if=/dev/urandom of="$HILF/brocken.bin" bs=1K count=32 status=none
    {
        for i in $(seq 1 200); do printf 'write %s/brocken.bin g%s\n' "$HILF" "$i"; done
    } > "$HILF/e1.txt"
    debugfs -w -f "$HILF/e1.txt" "$img" >/dev/null 2>&1
    {
        for i in $(seq 1 2 200); do printf 'rm g%s\n' "$i"; done
    } > "$HILF/e2.txt"
    debugfs -w -f "$HILF/e2.txt" "$img" >/dev/null 2>&1

    ext4_befehle "$BAUM" > "$HILF/e3.txt"
    {
        cat "$HILF/e3.txt"
        printf 'symlink verweis.txt %s\n' "$VERWEIS_KURZ"
        printf 'symlink langverweis.txt %s\n' "$VERWEIS_LANG"
    } > "$HILF/e4.txt"
    debugfs -w -f "$HILF/e4.txt" "$img" >"$HILF/e4.log" 2>&1

    {
        for i in $(seq 2 2 200); do printf 'rm g%s\n' "$i"; done
    } > "$HILF/e5.txt"
    debugfs -w -f "$HILF/e5.txt" "$img" >/dev/null 2>&1

    e2fsck -fyD "$img" >"$HILF/fsck.log" 2>&1
    local rc=$?
    if [ $rc -gt 1 ]; then
        echo "bild: e2fsck meldet $rc auf $img"
        sed 's/^/    /' "$HILF/fsck.log" | tail -8
        return 1
    fi
    return 0
}

echo "bild: ext4 (1024er Bloecke) ..."
ext4_bauen "$AUS/ext4.img" 1024 48 0 || { echo "bild: mkfs.ext4 fehlgeschlagen"; exit 3; }

echo "bild: ext4 (4096er Bloecke) ..."
ext4_bauen "$AUS/ext4-4k.img" 4096 48 0 || exit 3

tiefe=$(python3 tools/fremdfs/ext4info.py tiefe "$AUS/ext4.img" gross.bin 2>/dev/null)
echo "bild: Extent-Baumtiefe von gross.bin (1024er): ${tiefe:-?}"
printf '%s\n' "${tiefe:-0}" > "$AUS/ext4-tiefe.txt"
extents=$(python3 tools/fremdfs/ext4info.py extents "$AUS/ext4.img" gross.bin 2>/dev/null)
printf '%s\n' "${extents:-0}" > "$AUS/ext4-extents.txt"
htree=$(python3 tools/fremdfs/ext4info.py htree "$AUS/ext4.img" viele 2>/dev/null)
printf '%s\n' "${htree:-0}" > "$AUS/ext4-htree.txt"
echo "bild: gross.bin hat ${extents:-?} Extents; /viele ist htree=${htree:-?}"

echo "bild: ext4 unsauber (Journal, needs_recovery) ..."
ext4_bauen "$AUS/ext4-schmutzig.img" 1024 48 1 || exit 3
python3 - "$AUS/ext4-schmutzig.img" <<'PY'
import struct, sys
with open(sys.argv[1], 'r+b') as f:
    f.seek(1024)
    sb = bytearray(f.read(1024))
    # ACHTUNG, HIER LAG EIN FEHLER: s_state steht bei 0x3A, bei 0x38
    # steht die MAGIE (0xEF53). Wer hier 0x38 schreibt, zerstoert die
    # Magie und baut aus Versehen das KAPUTTE Abbild noch einmal --
    # und die Gegenprobe "unsauber wird erkannt" haette dann in
    # Wahrheit "keine Magie wird erkannt" gemessen.
    struct.pack_into('<H', sb, 0x3A, 0)              # s_state: nicht sauber
    inc = struct.unpack_from('<I', sb, 0x60)[0] | 0x4  # NEEDS_RECOVERY
    struct.pack_into('<I', sb, 0x60, inc)
    f.seek(1024)
    f.write(sb)
PY

# ---------------------------------------------------------- Gegenproben
echo "bild: die Gegenproben ..."
# 1. kaputte Magie: 0xEF53 bei 1024+0x38 zerstoert.
cp --sparse=always "$AUS/ext4.img" "$AUS/kaputt-ext4.img"
printf '\x00\x00' | dd of="$AUS/kaputt-ext4.img" bs=1 seek=$((1024 + 0x38)) \
    conv=notrunc status=none

leer_anlegen "$AUS/fat-als-ext4.img" 48
if command -v mkfs.vfat >/dev/null 2>&1; then
    mkfs.vfat -F 32 "$AUS/fat-als-ext4.img" >/dev/null 2>&1
fi

cp --sparse=always "$AUS/ext4.img" "$AUS/kurz-ext4.img"
python3 - "$AUS/kurz-ext4.img" <<'PYEOF'
import os, sys
# 24 von 48 MiB: der Superblock nennt mehr Bloecke, als das Geraet hat.
os.truncate(sys.argv[1], 24 * 1024 * 1024)
PYEOF

# ---------------------------------------------------------------- NTFS
echo "bild: NTFS ..."
leer_anlegen "$AUS/ntfs.img" 80
if ! mkntfs -F -Q -c 4096 -L OSUMTEST "$AUS/ntfs.img" >/dev/null 2>&1; then
    echo "bild: mkntfs fehlgeschlagen"
    exit 3
fi
if ! "$HILF/ntfsbaum" "$AUS/ntfs.img" "$BAUM" >"$HILF/ntfs.log" 2>&1; then
    echo "bild: ntfsbaum fehlgeschlagen"
    sed 's/^/    /' "$HILF/ntfs.log" | head -10
    exit 3
fi

if command -v ntfsfix >/dev/null 2>&1; then
    if ntfsfix -n "$AUS/ntfs.img" >"$HILF/fix.log" 2>&1; then
        echo "bild: ntfsfix -n sagt: in Ordnung"
    else
        echo "bild: WARNUNG -- ntfsfix -n meldet etwas:"
        sed 's/^/    /' "$HILF/fix.log" | tail -5
    fi
fi
if command -v ntfscat >/dev/null 2>&1; then
    nfehl=0
    while read -r summe pfad; do
        ist=$(ntfscat "$AUS/ntfs.img" "/$pfad" 2>/dev/null | sha256sum | cut -d' ' -f1)
        [ "$ist" = "$summe" ] || { nfehl=$((nfehl+1)); echo "    ntfs abweichung: $pfad"; }
    done < <(head -20 "$AUS/baum.sha")
    echo "bild: NTFS-Gegenlesung mit ntfscat: $nfehl Abweichungen (von 20)"
fi

# NTFS-Gegenprobe: zerstoerte Kennung "NTFS    " bei +3.
cp --sparse=always "$AUS/ntfs.img" "$AUS/kaputt-ntfs.img"
printf 'XXXX' | dd of="$AUS/kaputt-ntfs.img" bs=1 seek=3 conv=notrunc status=none

echo "bild: fertig in $AUS"
ls -la "$AUS" | sed 's/^/  /'
