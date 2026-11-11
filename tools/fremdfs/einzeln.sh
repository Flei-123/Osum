#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
ULD=kernel/user/user.ld
PROGS="sh cat echo ls cp rm mkdir wc true false mount umount fremdfs"

ART=${1:?usage: einzeln.sh <art> <abbild> [befehl]}
ABBILD=${2:?usage: einzeln.sh <art> <abbild> [befehl]}
BEFEHL=${3:-fremdfs $ART /dev/hdb1 /mnt}

W=${OSUM_FF_WORK:-$(mktemp -d)}
. tools/lib/tmpdir.sh
osum_tmp_guard "${OSUM_FF_WORK:-}" "$W"
mkdir -p "$W"
echo ">> Arbeitsverzeichnis: $W"

if [ ! -f "$W/k0.mb" ]; then
    echo ">> bauen ..."
    as --64 -o "$W/crt.o" kernel/user/crt.s
    bash tools/build-kernel.sh "$W/k0.mb" --stufe 0 > "$W/build.log" 2>&1 || {
        tail -20 "$W/build.log"; exit 1; }
    for p in $PROGS; do
        "$FIRNC" "kernel/user/$p.fi" -o "$W/$p.o" > "$W/e$p" 2>&1 || {
            echo "firnc scheitert an $p"; cat "$W/e$p" | head; exit 1; }
        ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
            -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" || exit 1
        strip --strip-all "$W/$p.elf"
    done
    MKARGS=""
    for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$W/$p.elf"; done
    bash tools/mkfsfi/mkfs.sh build "$W/root.img" 8192 \
        /bin/ /proc/ /dev/ /mnt/ $MKARGS > "$W/mkfs.log" 2>&1 || {
        tail -5 "$W/mkfs.log"; exit 1; }
fi

typ=83
[ "$ART" = ntfs ] && typ=7
[ "$ART" = vfat ] && typ=c
groesse=$(stat -c %s "$ABBILD")
python3 - "$W/zweite.img" $(( groesse / 1048576 + 2 )) <<'PYEOF'
import sys
ziel, mib = sys.argv[1], int(sys.argv[2])
with open(ziel, 'wb') as f:
    f.seek(mib * 1048576 - 1)
    f.write(b'\0')
PYEOF
printf 'label: dos\nstart=2048, type=%s\n' "$typ" | sfdisk "$W/zweite.img" >/dev/null 2>&1
dd if="$ABBILD" of="$W/zweite.img" bs=512 seek=2048 conv=notrunc status=none

cp "$W/root.img" "$W/live.img"
ACC=""
[ "$OSUM_QEMU_ACCEL" = kvm ] && ACC="-cpu host"
echo ">> Lauf: $BEFEHL"
timeout "${OSUM_FF_T:-300}" $QEMU_X86 $ACC -kernel "$W/k0.mb" -m 512 \
    -append "osum nokbd vfs script=$BEFEHL" \
    -serial "file:$W/aus.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$W/live.img,format=raw,if=ide,index=0" \
    -drive "file=$W/zweite.img,format=raw,if=ide,index=1" > /dev/null 2>&1
echo ">> Beendigungscode: $?"
echo ">> ---------------- serielle Ausgabe ----------------"
cat "$W/aus.txt" 2>/dev/null | tr -d '\000'
echo ">> --------------------------------------------------"
echo ">> alles in $W"
