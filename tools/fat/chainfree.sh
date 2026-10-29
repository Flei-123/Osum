#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh cat echo ls rm mount umount"
FILE_MIB=${CF_MIB:-40}
FS_MIB=${CF_FS_MIB:-64}
HARD=${CF_HARD:-3}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || exit 1
K=${1:-}
if [ -z "$K" ]; then
    bash tools/build-kernel.sh "$W/k0.mb" --stufe 0 > "$W/build.log" 2>&1 || { tail -15 "$W/build.log"; exit 1; }
    K="$W/k0.mb"
fi
as --64 -o "$W/crt.o" kernel/user/crt.s
MKARGS=""
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$W/$p.o" > "$W/e$p" 2>&1 || { echo "firnc $p"; head -5 "$W/e$p"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" || exit 1
    strip --strip-all "$W/$p.elf"
    MKARGS="$MKARGS /bin/$p=$W/$p.elf"
done

dd if=/dev/null of="$W/fat.fs" bs=1M seek="$FS_MIB" 2>/dev/null
mkfs.fat -F 32 -s 1 "$W/fat.fs" >/dev/null 2>&1 || { echo "mkfs.fat failed"; exit 1; }
head -c "$((FILE_MIB * 1048576))" /dev/zero > "$W/big.bin"
mcopy -i "$W/fat.fs" "$W/big.bin" ::BIG.BIN || { echo "mcopy failed"; exit 1; }
printf 'keep\n' > "$W/keep.txt"
mcopy -i "$W/fat.fs" "$W/keep.txt" ::KEEP.TXT || exit 1
fsck.fat -n "$W/fat.fs" >/dev/null 2>&1 && ok "image clean before" || bad "image not clean before"
dd if=/dev/null of="$W/disk.img" bs=1M seek="$((FS_MIB + 2))" 2>/dev/null
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$W/disk.img" >/dev/null 2>&1
dd if="$W/fat.fs" of="$W/disk.img" bs=512 seek=2048 conv=notrunc status=none

cat > "$W/s.sh" <<'SEOF'
echo "unlock hdb" > /dev/wlock
umount /mnt
mount /dev/hdb1 /mnt vfat
echo "@@mount-rc=$?"
cat /proc/uptime
rm /mnt/BIG.BIN
echo "@@rm-rc=$?"
cat /proc/uptime
ls /mnt
umount /mnt
echo @@end
SEOF
python3 tools/osum/mkfs.py build "$W/root.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $MKARGS \
    "/t/s.sh=$W/s.sh" > "$W/mkfs.log" 2>&1 || { tail -3 "$W/mkfs.log"; exit 1; }
ACC=""; [ "$OSUM_QEMU_ACCEL" = kvm ] && ACC="-cpu host"
timeout ${CF_TIMEOUT:-900} $QEMU_X86 $ACC -kernel "$K" -m 512 \
    -append "osum nokbd vfs nmihard=$HARD script=sh /t/s.sh;exit" \
    -serial "file:$W/out.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$W/root.img,format=raw,if=ide,index=0" \
    -drive "file=$W/disk.img,format=raw,if=ide,index=1" >/dev/null 2>&1
rc=$?
tr -d '\r\000' < "$W/out.txt" > "$W/clean.txt"
[ -n "${CF_SHOW:-}" ] && sed -n "/@@mount-rc/,/@@end/p" "$W/clean.txt"
[ "$rc" = 21 ] && ok "OS finished (rc 21)" || bad "OS rc=$rc"
grep -aq '@@mount-rc=0' "$W/clean.txt" && ok "FAT32 mounted" || bad "mount failed"
grep -aq '@@rm-rc=0' "$W/clean.txt" && ok "rm of the big file succeeded" || bad "rm failed"
grep -aq '^hang: cpu' "$W/clean.txt" && bad "freeze logger fired (hang)" || ok "no freeze logger report"
grep -aq 'KEEP.TXT\|keep.txt' "$W/clean.txt" && ok "other file still listed" || bad "other file missing"
dd if="$W/disk.img" of="$W/after.fs" bs=512 skip=2048 count=$((FS_MIB * 2048)) status=none
fsck.fat -n "$W/after.fs" > "$W/fsck.txt" 2>&1 && ok "fsck.fat clean after" || { bad "fsck.fat not clean"; head -5 "$W/fsck.txt"; }
mcopy -i "$W/after.fs" ::KEEP.TXT "$W/keep.out" 2>/dev/null && cmp -s "$W/keep.txt" "$W/keep.out" && ok "kept file intact" || bad "kept file damaged"
echo "CHAINFREE: $pass ok, $fail failed"
[ "$fail" = 0 ]
