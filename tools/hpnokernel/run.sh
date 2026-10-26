#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hpnokernel/run.sh -- HP-like disk (ESP 200 MiB FAT32 with Windows files, MSR, BitLocker NTFS, Recovery 861 MiB-like, free gap)
# installed beside from a stick whose kernel image is unreachable (no /boot/osum.mb, no readable stick ESP): the installer must refuse
# BEFORE writing anything (old code: wrote the partition, copied, then failed at "5/5 set up boot loader").
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
for t in sgdisk mkntfs mkfs.vfat mcopy python3 sha256sum; do
    command -v "$t" >/dev/null 2>&1 || { echo "HPNOKERNEL: $t missing"; exit 1; }
done
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

build() {
    mkdir -p "$2"
    ( cd "$1" && bash tools/usbimg/build.sh "$2" > "$2.log" 2>&1 )
}

make_disk() {
    local d=$1
    mkdir -p "$d"
    bash tools/gptview/mkhp.sh "$d" 256 || return 1
    local esp="$d/esp.part"
    dd if=/dev/zero of="$esp" bs=512 count=409600 status=none
    mkfs.vfat -F 32 -s 1 -S 512 -n SYSTEM "$esp" >/dev/null || return 1
    mmd -i "$esp" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot ::/EFI/Boot ::/EFI/HP
    head -c 2800000 /dev/urandom > "$d/blob"
    mcopy -i "$esp" "$d/blob" ::/EFI/Microsoft/Boot/bootmgfw.efi
    mcopy -i "$esp" "$d/blob" ::/EFI/Boot/bootx64.efi
    mcopy -i "$esp" "$d/blob" ::/EFI/HP/pad_with_long_name_to_force_lfn.bin
    dd if="$esp" of="$d/disk.img" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$esp" "$d/blob"
}

run_cli() {
    local bau=$1 disk=$2 ser=$3
    local work="$OUT/work.$$"
    mkdir -p "$work"
    cp -f "$bau/root.img" "$work/root.img"
    local zblk
    zblk=$(python3 tools/osum/mkfs.py where "$work/root.img" /etc/ziel 2>/dev/null | sed -n 's/.*first=\([0-9]*\).*/\1/p')
    [ -n "$zblk" ] && printf 'kons\n\0\0' | dd of="$work/root.img" bs=512 seek="$zblk" conv=notrunc status=none
    timeout 900 $QEMU_X86 -m 512 -kernel "$bau/osum.mb" \
        -append "osum vfs nokbd nosched noproc noring3 script=dualcli /dev/hdb --quelle /dev/hda --ja --name hdb;exit" \
        -serial "file:$ser" -display none -no-reboot \
        -drive "file=$work/root.img,format=raw,if=ide,index=0" \
        -drive "file=$disk,format=raw,if=ide,index=1" > "$work/qemu.log" 2>&1
    rm -rf "$work"
}

NEW=${NEW:-$OUT/new}
OLD=${OLD:-$OUT/old}
if [ ! -f "$NEW/osum.mb" ]; then build "$PWD" "$NEW" || { echo "HPNOKERNEL: build failed"; tail -n 5 "$NEW.log"; exit 1; }; fi
if [ ! -f "$OLD/osum.mb" ]; then
    mkdir -p "$OUT/oldsrc"
    git archive origin/main | tar -x -C "$OUT/oldsrc"
    cp -r vendor/firn/bin vendor/firn/lib "$OUT/oldsrc/vendor/firn/" 2>/dev/null
    build "$OUT/oldsrc" "$OLD" || { echo "HPNOKERNEL: old build failed"; tail -n 5 "$OLD.log"; exit 1; }
fi

echo "== 1. new code refuses before writing =="
make_disk "$OUT/d1" && ok "HP-like disk built" || { bad "disk"; echo "HPNOKERNEL: $pass passed, $fail failed"; exit 1; }
sum=$(sha256sum < "$OUT/d1/disk.img" | cut -d' ' -f1)
run_cli "$NEW" "$OUT/d1/disk.img" "$OUT/s1.txt"
tr -d '\000' < "$OUT/s1.txt" | grep -a '^dual:' | tail -4 | sed 's/^/        /'
grep -aq 'dual: kernel image missing' "$OUT/s1.txt" && ok "refuses: kernel image missing" || bad "no refusal line"
grep -aq 'dual: new p' "$OUT/s1.txt" && bad "partition was written" || ok "no partition entry written"
[ "$(sha256sum < "$OUT/d1/disk.img" | cut -d' ' -f1)" = "$sum" ] && ok "disk byte-identical after the refusal" || bad "disk changed"

echo "== 2. counter-proof: old code writes first and fails later =="
make_disk "$OUT/d2" || bad "disk 2"
sum2=$(sha256sum < "$OUT/d2/disk.img" | cut -d' ' -f1)
run_cli "$OLD" "$OUT/d2/disk.img" "$OUT/s2.txt"
tr -d '\000' < "$OUT/s2.txt" | grep -a '^dual:' | tail -3 | sed 's/^/        /'
[ "$(sha256sum < "$OUT/d2/disk.img" | cut -d' ' -f1)" != "$sum2" ] && ok "old code changed the disk although the kernel is unreachable (bug reproduced)" || bad "old code left the disk untouched"

echo "HPNOKERNEL: $pass passed, $fail failed"
[ "$fail" = 0 ]
