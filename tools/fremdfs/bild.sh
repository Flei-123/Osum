#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fremdfs/bild.sh -- DIE PRUEFBILDER, VOM WIRT GEBAUT.
#
# Der Kern dieser Runde ist eine Behauptung: Osum liest ext4 und NTFS
# richtig. Eine solche Behauptung ist nur so viel wert wie das, woran
# sie gemessen wird -- und gemessen wird sie hier an den ECHTEN
# Werkzeugen: `mkfs.ext4` und `debugfs` (e2fsprogs) legen das eine an,
# `mkntfs` und libntfs-3g das andere. Wenn Osum ein Oktett anders
# versteht als die, ist Osum im Unrecht.
#
# WARUM NICHT `mount -o loop`: dieser Baum wird in einem LXC-Behaelter
# gebaut, und dort gibt es weder /dev/loop* noch /dev/fuse. Also wird
# in die ABBILDER geschrieben statt in eingehaengte Dateisysteme --
# mit `debugfs` (dem Schreiber von e2fsprogs) und mit
# `tools/fremdfs/ntfsbaum.c` (der Bibliothek, die auch ntfs-3g
# benutzt, nur ohne FUSE darueber). Beides ist FREMDER Code, und
# genau darauf kommt es an.
#
#   bash tools/fremdfs/bild.sh <ausgabeverzeichnis>
#
# DER BAUM. Jeder Eintrag prueft etwas Bestimmtes:
#
#   /hallo.txt              die einfachste Datei ueberhaupt
#   /leer.bin               NULL OKTETTE -- ein Extent-Baum ohne Extents
#   /mittel.bin             200 KiB -- mehrere Bloecke, ein Extent
#   /gross.bin              ~6 MiB, ABSICHTLICH ZERSTUECKELT, damit der
#                           Extent-Baum TIEFE 1 bekommt (ein Indexknoten
#                           ueber den Blattknoten). Ohne die
#                           Zerstueckelung haette dieselbe Datei zwei
#                           Extents und Tiefe 0 -- der Baum bliebe
#                           ungeprueft. Gemessen wird die Tiefe, sie
#                           wird nicht gehofft.
#   /a/b/c/d/tief.txt       vier Ebenen tief
#   /umlaut-äöü.txt        Umlaute im Namen
#   /verweis.txt            symbolischer Verweis, INLINE (Ziel im Inode)
#   /langverweis.txt        symbolischer Verweis in einem DATENBLOCK
#   /viele/datei-0000..0511 512 Eintraege -- erzwingt bei ext4 einen
#                           htree-Index und bei NTFS einen $I30-Baum
#                           mit mehr als einem Knoten
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

AUS=${1:?usage: bild.sh <ausgabeverzeichnis>}
mkdir -p "$AUS"
AUS=$(cd "$AUS" && pwd)

for w in mkfs.ext4 debugfs mkntfs sha256sum gcc; do
    command -v "$w" >/dev/null 2>&1 || { echo "bild.sh: $w fehlt"; exit 2; }
done

BAUM=$(mktemp -d)
HILF=$(mktemp -d)
trap 'rm -rf "$BAUM" "$HILF"' EXIT

# Der Helfer, der NTFS fuellt.
if ! gcc -O2 -o "$HILF/ntfsbaum" tools/fremdfs/ntfsbaum.c -lntfs-3g 2>"$HILF/gcc.log"; then
    echo "bild.sh: ntfsbaum.c laesst sich nicht uebersetzen (ntfs-3g-dev fehlt?)"
    sed 's/^/    /' "$HILF/gcc.log" | head -10
    exit 2
fi

# ------------------------------------------------------------ der Baum
#
# DIE INHALTE SIND VORHERSAGBAR UND NICHT ZUFAELLIG. Wenn eine
# Pruefsumme nicht stimmt, will man SEHEN koennen, an welcher Stelle --
# und ein Muster aus `seq` laesst sich lesen.
echo "bild: den Baum bauen ..."
printf 'hallo aus orientos\n' > "$BAUM/hallo.txt"
: > "$BAUM/leer.bin"
# GENAU DIE ZAHL VON OKTETTEN, DIE DASTEHT. `seq ... | head -c N` gibt
# WENIGER als N, sobald der Zahlenvorrat vorher endet -- gemessen:
# `seq 1 900000` sind 6188895 Oktette, nicht 6291456. Eine Pruefdatei,
# die anders gross ist als der Name sagt, ist ein stiller Messfehler.
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

# Die Ziele der beiden Verweise. Der kurze passt in den Inode (bis 59
# Oktette stehen INLINE in i_block), der lange nicht.
VERWEIS_KURZ='hallo.txt'
VERWEIS_LANG="a/b/c/d/$(printf 'x%.0s' $(seq 1 90))"

# Die Pruefsummen des BAUMS. Beide Dateisysteme bekommen denselben
# Inhalt, also gilt dieselbe Liste fuer beide.
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
# Die Befehle fuer `debugfs` werden in eine Datei geschrieben und in
# EINEM Lauf ausgefuehrt -- ein Aufruf je Datei waere bei 512 Dateien
# 512 Laeufe und jedes Mal ein neues Oeffnen des Abbilds.
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
    dd if=/dev/zero of="$img" bs=1M count="$mib" status=none
    local opts='extent,dir_index,^has_journal'
    [ "$jrnl" = 1 ] && opts='extent,dir_index,has_journal'
    mkfs.ext4 -q -F -b "$bs" -O "$opts" -E root_owner=0:0 -I 256 \
        "$img" >/dev/null 2>&1 || return 1

    # 1. DIE ZERSTUECKELUNG. Erst viele Dateien anlegen, dann jede
    #    zweite loeschen, dann die grosse Datei schreiben: sie bekommt
    #    die Luecken und damit viele Extents. Gemessen wird danach,
    #    dass der Baum wirklich Tiefe > 0 hat.
    dd if=/dev/urandom of="$HILF/brocken.bin" bs=1K count=64 status=none
    {
        for i in $(seq 1 400); do printf 'write %s/brocken.bin g%s\n' "$HILF" "$i"; done
    } > "$HILF/e1.txt"
    debugfs -w -f "$HILF/e1.txt" "$img" >/dev/null 2>&1
    {
        for i in $(seq 1 2 400); do printf 'rm g%s\n' "$i"; done
    } > "$HILF/e2.txt"
    debugfs -w -f "$HILF/e2.txt" "$img" >/dev/null 2>&1

    # 2. Der eigentliche Baum.
    ext4_befehle "$BAUM" > "$HILF/e3.txt"
    {
        cat "$HILF/e3.txt"
        printf 'symlink verweis.txt %s\n' "$VERWEIS_KURZ"
        printf 'symlink langverweis.txt %s\n' "$VERWEIS_LANG"
    } > "$HILF/e4.txt"
    debugfs -w -f "$HILF/e4.txt" "$img" >"$HILF/e4.log" 2>&1

    # 3. Die uebriggebliebenen Brocken weg -- sie sollen den Baum
    #    nicht verfaelschen, nur die Zerstueckelung bewirkt haben.
    {
        for i in $(seq 2 2 400); do printf 'rm g%s\n' "$i"; done
    } > "$HILF/e5.txt"
    debugfs -w -f "$HILF/e5.txt" "$img" >/dev/null 2>&1

    # 4. DEN htree-INDEX WIRKLICH BAUEN LASSEN.
    #
    # `debugfs` legt Verzeichnisse nur LINEAR an -- auch mit 512
    # Eintraegen und gesetztem Merkmal `dir_index` bleibt das Bit
    # EXT4_INDEX_FL aus, und dann waere der htree-Weg des Treibers
    # ungeprueft, obwohl der Auftrag ihn ausdruecklich verlangt.
    # `e2fsck -fyD` ("Optimizing directories") baut die Indizes so,
    # wie der Kernel sie baut. Gemessen wird danach, dass das Bit
    # wirklich steht -- siehe `ext4info.py htree`.
    #
    # Nebenwirkung, und eine erwuenschte: `e2fsck` raeumt dabei die
    # Grabsteine der geloeschten Brocken weg (Eintraege mit Inode 0),
    # sodass die Verzeichniszahlen des Abbilds denen des Wirtsbaums
    # entsprechen.
    e2fsck -fyD "$img" >"$HILF/fsck.log" 2>&1
    local rc=$?
    # 0 = nichts zu tun, 1 = Fehler behoben. Beides ist hier richtig;
    # alles darueber ist ein kaputtes Pruefbild.
    if [ $rc -gt 1 ]; then
        echo "bild: e2fsck meldet $rc auf $img"
        sed 's/^/    /' "$HILF/fsck.log" | tail -8
        return 1
    fi
    return 0
}

echo "bild: ext4 (1024er Bloecke) ..."
ext4_bauen "$AUS/ext4.img" 1024 96 0 || { echo "bild: mkfs.ext4 fehlgeschlagen"; exit 3; }

echo "bild: ext4 (4096er Bloecke) ..."
ext4_bauen "$AUS/ext4-4k.img" 4096 96 0 || exit 3

# DIE TIEFE DES EXTENT-BAUMS WIRD GEMESSEN. Ohne diese Zeilen waere
# "der Treiber kann Extent-Baeume" eine Hoffnung und keine Zusage.
tiefe=$(python3 tools/fremdfs/ext4info.py tiefe "$AUS/ext4.img" gross.bin 2>/dev/null)
echo "bild: Extent-Baumtiefe von gross.bin (1024er): ${tiefe:-?}"
printf '%s\n' "${tiefe:-0}" > "$AUS/ext4-tiefe.txt"
extents=$(python3 tools/fremdfs/ext4info.py extents "$AUS/ext4.img" gross.bin 2>/dev/null)
printf '%s\n' "${extents:-0}" > "$AUS/ext4-extents.txt"
htree=$(python3 tools/fremdfs/ext4info.py htree "$AUS/ext4.img" viele 2>/dev/null)
printf '%s\n' "${htree:-0}" > "$AUS/ext4-htree.txt"
echo "bild: gross.bin hat ${extents:-?} Extents; /viele ist htree=${htree:-?}"

# ext4 MIT Journal und UNSAUBER ausgehaengt -- die Lage nach einem
# Absturz. s_state = 0 und das Bit NEEDS_RECOVERY, also genau das, was
# ein abgestuerztes Linux hinterlaesst.
echo "bild: ext4 unsauber (Journal, needs_recovery) ..."
ext4_bauen "$AUS/ext4-schmutzig.img" 1024 96 1 || exit 3
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
cp "$AUS/ext4.img" "$AUS/kaputt-ext4.img"
printf '\x00\x00' | dd of="$AUS/kaputt-ext4.img" bs=1 seek=$((1024 + 0x38)) \
    conv=notrunc status=none

# 2. ein FAT32 -- darf NICHT als ext4 durchgehen.
rm -f "$AUS/fat-als-ext4.img"
dd if=/dev/zero of="$AUS/fat-als-ext4.img" bs=1M count=96 status=none
if command -v mkfs.vfat >/dev/null 2>&1; then
    mkfs.vfat -F 32 "$AUS/fat-als-ext4.img" >/dev/null 2>&1
fi

# 3. abgeschnitten: der Superblock sagt eine Groesse, die das Geraet
#    nicht hat. Ein Treiber, der das nicht prueft, liest ins Leere.
cp "$AUS/ext4.img" "$AUS/kurz-ext4.img"
dd if="$AUS/ext4.img" of="$AUS/kurz-ext4.img" bs=1M count=48 status=none conv=notrunc
python3 - "$AUS/kurz-ext4.img" <<'PY'
import os, sys
os.truncate(sys.argv[1], 48 * 1024 * 1024)
PY

# ---------------------------------------------------------------- NTFS
echo "bild: NTFS ..."
rm -f "$AUS/ntfs.img"
dd if=/dev/zero of="$AUS/ntfs.img" bs=1M count=128 status=none
if ! mkntfs -F -Q -c 4096 -L OSUMTEST "$AUS/ntfs.img" >/dev/null 2>&1; then
    echo "bild: mkntfs fehlgeschlagen"
    exit 3
fi
if ! "$HILF/ntfsbaum" "$AUS/ntfs.img" "$BAUM" >"$HILF/ntfs.log" 2>&1; then
    echo "bild: ntfsbaum fehlgeschlagen"
    sed 's/^/    /' "$HILF/ntfs.log" | head -10
    exit 3
fi

# DAS ABBILD WIRD NICHT GEGLAUBT, SONDERN GEPRUEFT -- mit den
# Werkzeugen von ntfs-3g, bevor Osum es je zu sehen bekommt. Faellt
# hier etwas auf, ist das Messgeraet kaputt und nicht der Treiber.
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
cp "$AUS/ntfs.img" "$AUS/kaputt-ntfs.img"
printf 'XXXX' | dd of="$AUS/kaputt-ntfs.img" bs=1 seek=3 conv=notrunc status=none

echo "bild: fertig in $AUS"
ls -la "$AUS" | sed 's/^/  /'
