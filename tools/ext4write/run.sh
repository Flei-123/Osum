#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/firnenv.sh
ULD=kernel/user/user.ld
PROGS="sh cat echo ls cp rm mkdir mv rmdir mount umount shasum"
BS=${EXT4W_BS:-1024}
FEATURES=${EXT4W_FEATURES:-^metadata_csum,^64bit,^has_journal}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
for t in mkfs.ext4 e2fsck debugfs sfdisk qemu-system-x86_64; do
    command -v "$t" >/dev/null 2>&1 || { echo "EXT4WRITE: skipped, $t missing"; exit 0; }
done
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
python3 -I - "$W/src.bin" <<'PYEOF'
import sys
x = 12345; out = bytearray()
while len(out) < 300000:
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    out += x.to_bytes(4, "little")
open(sys.argv[1], "wb").write(bytes(out[:300000]))
PYEOF
SHA=$(sha256sum "$W/src.bin" | cut -d' ' -f1)
dd if=/dev/null of="$W/fs.img" bs=1M seek=16 2>/dev/null
mkfs.ext4 -q -F -b "$BS" -O "$FEATURES" -I 256 -N 4096 "$W/fs.img" >/dev/null 2>&1 || { echo "mkfs.ext4 failed"; exit 1; }
head -c 8192 "$W/src.bin" > "$W/hole.bin"
: > "$W/frag.cmd"
for i in $(seq 0 1199); do echo "write $W/hole.bin f$i" >> "$W/frag.cmd"; done
for i in $(seq 1 2 1199); do echo "rm f$i" >> "$W/frag.cmd"; done
debugfs -w -f "$W/frag.cmd" "$W/fs.img" >/dev/null 2>&1
e2fsck -fn "$W/fs.img" >/dev/null 2>&1 && ok "fresh image is clean" || bad "fresh image not clean"
dd if=/dev/null of="$W/disk.img" bs=1M seek=18 2>/dev/null
printf 'label: dos\nstart=2048, type=83\n' | sfdisk "$W/disk.img" >/dev/null 2>&1
dd if="$W/fs.img" of="$W/disk.img" bs=512 seek=2048 conv=notrunc status=none
cat > "$W/s.sh" <<'SEOF'
echo "unlock hdb" > /dev/wlock
umount /mnt
mount /dev/hdb1 /mnt ext4
echo "@@mount-rc=$?"
mkdir /mnt/d
cp /src.bin /mnt/d/a.bin
cp /src.bin /mnt/b.bin
mv /mnt/b.bin /mnt/d/c.bin
mkdir /mnt/e
rmdir /mnt/e
echo hello > /mnt/h.txt
rm /mnt/h.txt
cp /src.bin /mnt/h.txt
cp /src.bin /mnt/h.txt
shasum /mnt/d/a.bin /mnt/d/c.bin /mnt/h.txt
umount /mnt
echo @@end
SEOF
bash tools/mkfsfi/mkfs.sh build "$W/root.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $MKARGS \
    "/src.bin=$W/src.bin" "/t/s.sh=$W/s.sh" > "$W/mkfs.log" 2>&1 || { tail -3 "$W/mkfs.log"; exit 1; }
ACC=""; [ "$OSUM_QEMU_ACCEL" = kvm ] && ACC="-cpu host"
timeout "${EXT4W_TIMEOUT:-600}" $QEMU_X86 $ACC -kernel "$K" -m 512 \
    -append "osum nokbd vfs script=sh /t/s.sh;exit" \
    -serial "file:$W/out.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$W/root.img,format=raw,if=ide,index=0" \
    -drive "file=$W/disk.img,format=raw,if=ide,index=1" >/dev/null 2>&1
rc=$?
tr -d '\r\000' < "$W/out.txt" > "$W/clean.txt"
[ "$rc" = 21 ] && ok "OS finished (rc 21)" || bad "OS rc=$rc"
grep -aq '@@mount-rc=0' "$W/clean.txt" && ok "ext4 mounted read-write" || bad "mount failed"
n=$(grep -ac "^$SHA  /mnt/" "$W/clean.txt")
[ "$n" = 3 ] && ok "guest reads back 3 files with the source hash" || bad "guest hashes ($n of 3)"
dd if="$W/disk.img" of="$W/after.img" bs=512 skip=2048 status=none
e2fsck -fn "$W/after.img" > "$W/fsck.txt" 2>&1 && ok "host e2fsck -fn clean after guest writes" || { bad "host e2fsck reports errors"; head -15 "$W/fsck.txt"; }
for f in /d/a.bin /d/c.bin /h.txt; do
    h=$(debugfs -R "cat $f" "$W/after.img" 2>/dev/null | sha256sum | cut -d' ' -f1)
    [ "$h" = "$SHA" ] && ok "host reads $f: hash equal" || bad "host reads $f: hash differs"
done
debugfs -R "stat /e" "$W/after.img" 2>&1 | grep -qa "not found" && ok "removed dir /e is gone" || bad "dir /e still there"
debugfs -R "stat /b.bin" "$W/after.img" 2>&1 | grep -qa "not found" && ok "renamed source /b.bin is gone" || bad "/b.bin still there"
for f in /d/a.bin /d/c.bin /h.txt; do
    debugfs -R "ex $f" "$W/after.img" 2>/dev/null | grep -aq '^ *1/ *1 ' && ok "$f has a depth-1 extent tree" || bad "$f is not a depth-1 tree"
done
nex=$(debugfs -R "ex /d/a.bin" "$W/after.img" 2>/dev/null | grep -ac '^ *[01]/ *1 .* - ')
[ "$nex" -gt 8 ] && ok "a.bin has $nex extent lines (more than 4)" || bad "a.bin extent lines: $nex"
cp "$W/after.img" "$W/mut2.img"
debugfs -w -R "sif /d/a.bin blocks 8" "$W/mut2.img" >/dev/null 2>&1
e2fsck -fn "$W/mut2.img" >/dev/null 2>&1 && bad "MUTANT: wrong i_blocks not detected" || ok "MUTANT: wrong i_blocks of a deep tree turns e2fsck red"
cp "$W/after.img" "$W/mut.img"
debugfs -w -R "set_bg 0 free_blocks_count 1" "$W/mut.img" >/dev/null 2>&1
e2fsck -fn "$W/mut.img" >/dev/null 2>&1 && bad "MUTANT: broken group counter not detected" || ok "MUTANT: broken group counter turns e2fsck red"
echo "EXT4WRITE: $pass ok, $fail failed"
[ "$fail" = 0 ]
