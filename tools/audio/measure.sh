#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
ULD=kernel/user/user.ld
PROGS="sh echo cat ls play"

MEDIA=${1:-/ton.wav}
PLAYOPT=${TON_PLAYOPT:-}
SMP=${2:-4}
QUELLE=${3:-ide}
TMPD=${TON_TMPD:-$(mktemp -d)}
KEEP=${TON_KEEP:-0}
mkdir -p "$TMPD"
[ "$KEEP" = 1 ] || trap 'rm -rf "$TMPD"' EXIT

echo "== bauen =="
bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/build.txt" 2>&1 \
    || { echo "the kernel does not build:"; tail -30 "$TMPD/build.txt"; exit 1; }
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null
for p in $PROGS; do
    "$FIRNC" -o "$TMPD/$p.o" "kernel/user/$p.fi" > "$TMPD/$p.log" 2>&1 || {
        echo "$p uebersetzt nicht"; tail -20 "$TMPD/$p.log"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2> >(grep -vE \
        'GNU-stack|deprecated|RWX' >&2) || { echo "$p bindet nicht"; exit 1; }
done
bash tools/hda/mkmedia.sh "$TMPD/m" > "$TMPD/media.txt" 2>&1
SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
for f in "$TMPD"/m/*; do SPEC="$SPEC /$(basename "$f")=$f"; done
SEKT=$(( $(du -cb "$TMPD"/m/* "$TMPD"/*.elf 2>/dev/null | tail -1 | cut -f1) * 3 / 2 / 512 + 4096 ))
[ "$SEKT" -lt 16384 ] && SEKT=16384
bash tools/mkfsfi/mkfs.sh build "$TMPD/disk.img" "$SEKT" $SPEC > "$TMPD/mkfs.txt" 2>&1 \
    || { echo mkfs; tail -5 "$TMPD/mkfs.txt"; exit 1; }
echo "  Platte: $SEKT Sektoren, $(stat -c%s "$TMPD/disk.img") Oktette, Medien: $(ls "$TMPD/m" | tr '\n' ' ')"

HDADEV="-device intel-hda -device hda-duplex,audiodev=snd0"
aud="-audiodev wav,id=snd0,path=$TMPD/out.wav,out.frequency=48000,out.channels=2,out.format=s16"
rm -f "$TMPD/out.wav"
DISKARG="-drive file=$TMPD/disk.img,format=raw,if=ide,index=0"
[ "$QUELLE" = ram ] && DISKARG="-initrd $TMPD/disk.img"
EXTRA=""
[ "$QUELLE" = ram ] && EXTRA="modfs"
echo "== measure: /bin/play $PLAYOPT $MEDIA at -smp $SMP, source $QUELLE =="
timeout 600 $QEMU_X86 -kernel "$TMPD/k.mb" -m 512 -smp "$SMP" \
    -append "osum nokbd audio nosounds $EXTRA script=/bin/play $PLAYOPT $MEDIA;exit" \
    -serial "file:$TMPD/out.txt" -display none -no-reboot $aud $HDADEV \
    $DISKARG \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
echo "  Rueckgabe: $?"
echo "-- was /bin/play sagt ------------------------------------------"
sed -n '/art:/,$p' "$TMPD/out.txt" | sed 's/^/  /' | head -40
echo "-- what came out of the device --------------------------------------"
if [ -s "$TMPD/out.wav" ]; then
    python3 tools/hda/wavcheck.py "$TMPD/out.wav" --hz 440 --rate 48000 2>&1 | sed 's/^/  /'
else
    echo "  NO output -- out.wav is empty"
fi
[ "$KEEP" = 1 ] && echo "(Arbeitsstand bleibt in $TMPD)"
exit 0
