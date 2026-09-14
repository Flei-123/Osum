#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fremdfs/tempo.sh -- WIE SCHNELL GELESEN WIRD, in MB/s.
#
# Der Auftrag dieser Runde verlangt eine Zahl gegen das EIGENE
# Dateisystem. `run.sh` misst die Dauer eines ganzen Durchgangs -- das
# ist ehrlich, aber darin steckt der Start des Kernels, das Anlegen von
# 520 Pruefsummen und die Ausgabe ueber die serielle Schnittstelle.
# Fuer eine Zahl in MB/s taugt das nicht.
#
# Hier wird deshalb genau EINE Sache gemessen: EINE Datei von 2 MB
# ganz lesen, ohne sie zu hashen, mit der Uhr des Kernels davor und
# danach. Dreimal je Dateisystem, und die Zeit des SCHNELLSTEN Laufs
# zaehlt -- die anderen enthalten das, was die Maschine sonst noch tat.
#
# WARUM 2 MB UND NICHT DIE 6 MiB DES PRUEFBAUMS: eine Datei auf OFS
# kann in dieser Fassung hoechstens 2134016 Oktette gross sein (acht
# direkte Bloecke, 64 ueber den einfach und 4096 ueber den doppelt
# indirekten -- siehe `kernel/fs.fi` und docs/OFS-LIMITS.md). Die
# grosse Datei des Pruefbaums passt dort nicht hinein, und ohne einen
# Wert fuer OFS gaebe es keinen Vergleich. 2000000 Oktette passen auf
# ALLE DREI -- und nur dann ist die Zahl eine Aussage ueber die
# Treiber und nicht ueber die Grenzen des einen Dateisystems.
#
# Dieselbe Datei liegt dazu auf OFS, dem eigenen Dateisystem. Der
# Vergleich ist damit fair: dieselbe Maschine, dieselbe Platte,
# dieselbe Datei, derselbe Weg durch die VFS-Schicht.
#
#   bash tools/fremdfs/tempo.sh [bildverzeichnis]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh cat echo ls mount umount fftempo"

BILD=${1:-}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

if [ -z "$BILD" ]; then
    BILD="$W/bild"
    bash tools/fremdfs/bild.sh "$BILD" >/dev/null 2>&1 || {
        echo "tempo: die Abbilder lassen sich nicht bauen"; exit 1; }
fi

echo ">> bauen ..."
as --64 -o "$W/crt.o" kernel/user/crt.s
bash tools/build-kernel.sh "$W/k0.mb" --stufe 0 > "$W/build.log" 2>&1 || {
    tail -20 "$W/build.log"; exit 1; }
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$W/$p.o" > "$W/e$p" 2>&1 || {
        echo "firnc scheitert an $p:"; head -8 "$W/e$p"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" || exit 1
    strip --strip-all "$W/$p.elf"
done

# Die 2-MB-Datei liegt auch auf der WURZELPLATTE (OFS) -- das ist der
# Vergleichswert.
python3 - "$W/gross.bin" 2000000 <<'PYEOF'
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

MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$W/$p.elf"; done
python3 tools/osum/mkfs.py build "$W/root.img" 20000 \
    /bin/ /proc/ /dev/ /mnt/ $MKARGS "/gross.bin=$W/gross.bin" \
    > "$W/mkfs.log" 2>&1 || { tail -5 "$W/mkfs.log"; exit 1; }

partition() { # quelle ziel typ
    local groesse; groesse=$(stat -c %s "$1")
    python3 - "$2" $(( groesse / 1048576 + 2 )) <<'PYEOF'
import sys
ziel, mib = sys.argv[1], int(sys.argv[2])
with open(ziel, 'wb') as f:
    f.seek(mib * 1048576 - 1)
    f.write(b'\0')
PYEOF
    printf 'label: dos\nstart=2048, type=%s\n' "$3" | sfdisk "$2" >/dev/null 2>&1
    dd if="$1" of="$2" bs=512 seek=2048 conv=notrunc status=none
}
partition "$BILD/ext4.img" "$W/e.img" 83
partition "$BILD/ntfs.img" "$W/n.img" 7

ACC=""
[ "$OSUM_QEMU_ACCEL" = kvm ] && ACC="-cpu host"

lauf() { # name zweite befehl
    cp "$W/root.img" "$W/live.img"
    local drives=(-drive "file=$W/live.img,format=raw,if=ide,index=0")
    [ -n "$2" ] && drives+=(-drive "file=$2,format=raw,if=ide,index=1")
    timeout 300 $QEMU_X86 $ACC -kernel "$W/k0.mb" -m 512 \
        -append "osum nokbd vfs script=$3" \
        -serial "file:$W/$1.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "${drives[@]}" > /dev/null 2>&1
    grep -a -m1 '^tempo: ms = ' "$W/$1.txt" 2>/dev/null \
        | sed 's/.* = //' | tr -d '\r\000'
}

mbs() { # ms
    [ -z "${1:-}" ] || [ "${1:-0}" -eq 0 ] 2>/dev/null && { echo "?"; return; }
    python3 -c "print(f'{2000000/1048576/($1/1000):.1f}')"
}

best() { # name zweite befehl
    local a b c
    a=$(lauf "$1-1" "$2" "$3"); b=$(lauf "$1-2" "$2" "$3"); c=$(lauf "$1-3" "$2" "$3")
    python3 -c "
xs=[x for x in ['$a','$b','$c'] if x.isdigit()]
print(min(int(x) for x in xs) if xs else 0)"
}

echo ">> messen (je drei Laeufe, der schnellste zaehlt) ..."
ms_ofs=$(best ofs "" "fftempo /gross.bin 2000000")
ms_ext4=$(best ext4 "$W/e.img" "mount /dev/hdb1 /mnt ext4 -r;fftempo /mnt/gross.bin 2000000")
ms_ntfs=$(best ntfs "$W/n.img" "mount /dev/hdb1 /mnt ntfs -r;fftempo /mnt/gross.bin 2000000")

echo
printf '%-8s %8s %10s\n' "system" "ms" "MB/s"
printf '%-8s %8s %10s\n' "ofs"  "$ms_ofs"  "$(mbs "$ms_ofs")"
printf '%-8s %8s %10s\n' "ext4" "$ms_ext4" "$(mbs "$ms_ext4")"
printf '%-8s %8s %10s\n' "ntfs" "$ms_ntfs" "$(mbs "$ms_ntfs")"
echo
echo "2000000 Oktette am Stueck, Puffer 4096 Oktette, accel=$OSUM_QEMU_ACCEL"
