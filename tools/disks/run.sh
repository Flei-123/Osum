#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/disks/run.sh -- THE DISK MANAGER, READ SIDE (docs/DISKS.md stage D-0).
#
#   bash tools/disks/run.sh
#
# 1. lib/disks/table.fi on image files, on the host: a GPT (primary + backup), an MBR, a GPT with one flipped byte in
#    the entry array, one with a flipped byte in the header, a disk of zeros. The listing must be EXACTLY the one
#    mkdisk.py computed from its own numbers (the counter-proofs are the two broken tables: they must read as none).
# 2. (stage D-0b) /bin/diskctl in the VM on the same images -- see the second part.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
FIRNC=vendor/firn/bin/firnc

echo "== 1. the partition table reader on image files =="
python3 tools/disks/mkdisk.py "$D" || { echo "DISKS: mkdisk failed"; exit 1; }
if FIRNLIB="$(pwd)/lib" "$FIRNC" -o "$D/unit" tools/disks/unit.fi > "$D/cc.log" 2>&1; then
    ok "lib/disks/table.fi builds with tools/disks/unit.fi"
else
    bad "unit.fi does not build"; head -20 "$D/cc.log" | sed 's/^/        /'
    echo "DISKS: $pass passed, $fail failed"; exit 1
fi
for n in gpt mbr badcrc badhdr empty; do
    mkdir -p "$D/run-$n"; cp "$D/$n.img" "$D/run-$n/disk.img"
    ( cd "$D/run-$n" && "$D/unit" > out.txt 2>&1 )
    if cmp -s "$D/run-$n/out.txt" "$D/expect-$n.txt"; then
        ok "$n.img: $(head -1 "$D/run-$n/out.txt")"
    else
        bad "$n.img: expected / got"; diff "$D/expect-$n.txt" "$D/run-$n/out.txt" | sed 's/^/        /' | head -8
    fi
done

# ---------------------------------------------------------------------------------------------------
echo "== 2. /bin/diskctl in the VM: the system disk and a second disk with a GPT =="
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "   (qemu is not there -- part 2 skipped)"
    echo "DISKS: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit
fi
PROGS="diskctl sh echo ls cat"
bash tools/build-kernel.sh "$D/k0.mb" > "$D/k0.log" 2>&1 || { bad "the kernel does not build"; tail -5 "$D/k0.log"; echo "DISKS: $pass passed, $fail failed"; exit 1; }
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/bin.log" 2>&1 && ok "the kernel and $(echo $PROGS | wc -w) programs build" \
    || { bad "programs do not build"; head -10 "$D/bin.log"; echo "DISKS: $pass passed, $fail failed"; exit 1; }
MK=""
for p in $PROGS; do MK="$MK /bin/$p=$D/bin/$p.elf"; done
python3 tools/osum/mkfs.py build "$D/root.img" 4096 /bin/ /dev/ /mnt/ $MK > "$D/mkfs.log" 2>&1 || { bad "mkfs"; cat "$D/mkfs.log"; exit 1; }
for n in gpt mbr badcrc; do
    mkdir -p "$D/vm-$n"
    cp "$D/root.img" "$D/vm-$n/hda.img"; cp "$D/$n.img" "$D/vm-$n/hdb.img"
    timeout 120 qemu-system-x86_64 -accel kvm -kernel "$D/k0.mb" -m 256 \
        -append "osum nokbd vfs nopart script=diskctl list;exit" \
        -serial "file:$D/vm-$n/serial.txt" -display none -no-reboot \
        -drive "file=$D/vm-$n/hda.img,format=raw,if=ide,index=0" \
        -drive "file=$D/vm-$n/hdb.img,format=raw,if=ide,index=1" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    S="$D/vm-$n/serial.txt"
    if grep -qa '^disk /dev/hda sectors=[0-9]* table=none' "$S"; then
        ok "$n: the system disk (a whole-disk file system) is listed as table=none"
    else
        bad "$n: no line for /dev/hda"; grep -a '^disk' "$S" | head -3 | sed 's/^/        /'
    fi
    grep -qa '^  whole disk: mounted at /$' "$S" && ok "$n: and it says where it is mounted (/)" || bad "$n: hda is not shown as mounted at /"
    exp=$(head -1 "$D/expect-$n.txt")
    sch=$(echo "$exp" | sed -E 's/scheme ([a-z]+) .*/\1/')
    if grep -qa "^disk /dev/hdb sectors=32768 table=$sch" "$S"; then
        ok "$n: /dev/hdb reads as table=$sch, 32768 sectors"
    else
        bad "$n: /dev/hdb line missing or wrong"; grep -a '^disk' "$S" | sed 's/^/        /' | head -4
    fi
done
S="$D/vm-gpt/serial.txt"
grep -qa '^  1 start=2048 sectors=2048 kind=efi name=EFI' "$S" && ok "gpt: partition 1 is the EFI partition" || bad "gpt: partition 1 wrong"
grep -qa '^  2 start=4096 sectors=16384 kind=ofs name=OrientOS' "$S" && ok "gpt: partition 2 is OrientOS (ofs)" || bad "gpt: partition 2 wrong"
grep -qa '^  3 start=20480 sectors=8192 kind=basic name=data' "$S" && ok "gpt: partition 3 is data (basic)" || bad "gpt: partition 3 wrong"
S="$D/vm-mbr/serial.txt"
grep -qa '^  1 start=2048 sectors=8192 kind=fat32' "$S" && ok "mbr: partition 1 is fat32" || bad "mbr: partition 1 wrong"
grep -qa '^  2 start=10240 sectors=16384 kind=linux' "$S" && ok "mbr: partition 2 is linux" || bad "mbr: partition 2 wrong"
S="$D/vm-badcrc/serial.txt"
grep -qa '^  [0-9] start=' "$S" && bad "badcrc: a partition of a table with a wrong checksum was listed" \
    || ok "badcrc: a table with a wrong checksum lists no partition (the counter-proof)"

# ---------------------------------------------------------------------------------------------------
echo "== 3. /bin/disks, the window, on the same second disk =="
bash tools/toolbench/build.sh "$D/win" app=/bin/disks progs="disks explorer" second="$D/gpt.img" shot=allein extra="vfs nopart" \
    wait=12 last=140 accel=kvm > "$D/win.log" 2>&1
W="$D/win/serial.txt"
grep -qa '^disks: ready n=2 ' "$W" && ok "the window found two disks" || { bad "the window did not find two disks"; grep -a '^disks' "$W" | head -3 | sed 's/^/        /'; }
grep -qa '^disks: disk 1 /dev/hdb sectors=32768 table=gpt' "$W" && ok "it reports /dev/hdb as a GPT of 32768 sectors" || bad "no hdb line"
grep -qa '^disks: part 1 0 start=2048 sectors=2048 kind=efi mount=-' "$W" && ok "partition 1 of hdb: efi, not mounted" || bad "partition 1 line wrong"
grep -qa '^disks: part 1 2 start=20480 sectors=8192 kind=basic' "$W" && ok "partition 3 of hdb: basic" || bad "partition 3 line wrong"
GEO=$(grep -a '^disks: ready' "$W" | tail -1)
BW=$(echo "$GEO" | sed -nE 's/.* w=([0-9]+).*/\1/p'); BH=$(echo "$GEO" | sed -nE 's/.* h=([0-9]+).*/\1/p')
WX=$(echo "$GEO" | sed -nE 's/.* x=([0-9]+).*/\1/p'); WY=$(echo "$GEO" | sed -nE 's/.* y=([0-9]+).*/\1/p')
if [ -s "$D/win/allein.ppm" ] && [ -n "${BW:-}" ]; then
    python3 tools/themestore/shotcheck.py "$D/win/allein.ppm" "$W" --window="$WX","$WY","$BW","$BH" > "$D/shot.txt" 2>&1
    cat "$D/shot.txt" | head -3 | sed 's/^/        /'
    cut=$(grep -oE 'cut [0-9]+' "$D/shot.txt" | grep -oE '[0-9]+'); empty=$(grep -oE 'empty [0-9]+' "$D/shot.txt" | grep -oE '[0-9]+')
    [ "${cut:-9}" = 0 ] && ok "no label is cut off" || bad "labels are cut off: ${cut:-?}"
    [ "${empty:-9}" = 0 ] && ok "no label is empty" || bad "empty labels: ${empty:-?}"
    mkdir -p docs/shots/disks; cp "$D/win/allein.png" docs/shots/disks/disks-window.png 2>/dev/null || true
else
    bad "no picture of the window"
fi
echo "DISKS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
