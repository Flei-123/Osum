#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=vendor/firn/bin/firnc
ULD=kernel/user/user.ld
PROGS="sh cat echo ls cp rm mkdir wc true false mount umount"
OLDREF=${OLDREF:-}
W=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] && { mkdir -p "$KEEP"; cp "$W"/out-*.txt "$W"/*.log "$KEEP"/ 2>/dev/null; }; rm -rf "$W"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnt() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }

echo "== 1. build =="
as --64 -o "$W/crt.o" kernel/user/crt.s
for p in $PROGS; do
    "$FIRNC" "kernel/user/$p.fi" -o "$W/$p.o" > "$W/e$p" 2>&1 || { bad "firnc $p"; head -5 "$W/e$p"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" || exit 1
    strip --strip-all "$W/$p.elf"
done
build_kernel() {
    (cd "$1" && bash tools/build-kernel.sh "$2" --stufe 0 > "$2.log" 2>&1) || { tail -5 "$2.log"; return 1; }
}
build_kernel "$ROOT" "$W/k-new.mb" && ok "kernel builds" || { bad "kernel build"; exit 1; }

echo "== 2. images =="
printf 'root-file-content\n' > "$W/root.txt"
printf 'seed-from-second-disk\n' > "$W/seed.txt"
printf 'nested-file\n' > "$W/nested.txt"
cat > "$W/s.sh" <<'SH'
echo BEGIN
mount /dev/hdb1 /mnt ofs
echo MOUNT-RC-DONE
cat /mnt/seed.txt
ls /mnt
cat /mnt/d/nested.txt
echo written-on-second > /mnt/new.txt
cat /mnt/new.txt
mkdir /mnt/made
cat /root.txt
ls /
umount /mnt
echo UMOUNT-DONE
mount /dev/hdb1 /mnt ofs
cat /mnt/new.txt
cat /mnt/seed.txt
rm /mnt/new.txt
umount /mnt
echo END
SH
MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$W/$p.elf"; done
python3 tools/osum/mkfs.py build "$W/root.img" 8192 /bin/ /proc/ /dev/ /mnt/ /t/ /root.txt="$W/root.txt" /t/s.sh="$W/s.sh" $MKARGS > "$W/mkfs-root.log" 2>&1 || { bad "root image"; tail -3 "$W/mkfs-root.log"; exit 1; }
python3 tools/osum/mkfs.py build "$W/part.img" 4096 /d/ /seed.txt="$W/seed.txt" /d/nested.txt="$W/nested.txt" > "$W/mkfs-part.log" 2>&1 || { bad "partition image"; tail -3 "$W/mkfs-part.log"; exit 1; }
python3 - "$W/second.img" <<'PY'
import sys
with open(sys.argv[1], 'wb') as f:
    f.seek((2048 + 4096 + 64) * 512 - 1)
    f.write(b'\0')
PY
printf 'label: dos\nstart=2048, size=4096, type=83\n' | sfdisk "$W/second.img" > /dev/null 2>&1
dd if="$W/part.img" of="$W/second.img" bs=512 seek=2048 conv=notrunc status=none
cp "$W/root.img" "$W/root0.img"
cp "$W/second.img" "$W/second0.img"
sha256sum "$W/root0.img" "$W/second0.img" | cut -d' ' -f1 > "$W/before.sum"

run() {
    cp "$W/root0.img" "$W/live-$1.img"
    cp "$W/second0.img" "$W/second-$1.img"
    local acc=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && acc="-cpu host"
    timeout 240 $QEMU_X86 $acc -kernel "$2" -m 512 \
        -append "osum nokbd vfs nowlock script=sh /t/s.sh;exit" \
        -serial "file:$W/serial-$1.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$W/live-$1.img,format=raw,if=ide,index=0" \
        -drive "file=$W/second-$1.img,format=raw,if=ide,index=1" > /dev/null 2>&1
    tr -d '\000' < "$W/serial-$1.txt" > "$W/out-$1.txt"
}

echo "== 3. run: mount OFS on the second disk =="
run new "$W/k-new.mb"
S="$W/out-new.txt"
has "$S" "BEGIN" "script started"
has "$S" "seed-from-second-disk" "file of the second disk is readable"
has "$S" "nested-file" "nested directory of the second disk is readable"
has "$S" "written-on-second" "file written on the second disk reads back"
has "$S" "root-file-content" "root file still readable while the second disk is mounted"
has "$S" "UMOUNT-DONE" "umount returns"
has "$S" "END" "script ran to the end"
hasnt "$S" "panic" "no panic"
n=$(grep -ac "written-on-second" "$S")
[ "$n" -ge 2 ] && ok "written file survives umount and remount ($n)" || bad "written file lost after remount ($n)"

echo "== 4. the host looks at both disks =="
dd if="$W/second-new.img" of="$W/part-after.img" bs=512 skip=2048 count=4096 status=none
python3 tools/osum/mkfs.py list "$W/part-after.img" > "$W/part-list.txt" 2>&1
python3 tools/osum/mkfs.py list "$W/live-new.img" > "$W/root-list.txt" 2>&1
has "$W/part-list.txt" "made" "directory created in the guest is on the second disk"
hasnt "$W/part-list.txt" "new.txt" "removed file is gone on the second disk"
hasnt "$W/root-list.txt" "made" "root disk has no stray directory"
hasnt "$W/root-list.txt" "seed.txt" "root disk has no file of the second disk"
hasnt "$W/root-list.txt" "new.txt" "root disk has no file written to the second disk"

if [ -n "$OLDREF" ]; then
    echo "== 5. counter-proof: the same run on $OLDREF =="
    OLDWT="$W/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    rm -rf "$OLDWT/vendor/firn/bin" "$OLDWT/vendor/firn/lib"
    ln -s "$ROOT/vendor/firn/bin" "$OLDWT/vendor/firn/bin"
    ln -s "$ROOT/vendor/firn/lib" "$OLDWT/vendor/firn/lib"
    if build_kernel "$OLDWT" "$W/k-old.mb"; then
        run old "$W/k-old.mb"
        dd if="$W/live-old.img" of=/dev/null bs=512 count=1 status=none
        python3 tools/osum/mkfs.py list "$W/live-old.img" > "$W/root-list-old.txt" 2>&1
        o=0
        grep -qaF "seed-from-second-disk" "$W/out-old.txt" || o=$((o+1))
        grep -qaF "new.txt" "$W/root-list-old.txt" && o=$((o+1))
        [ "$o" -ge 1 ] && ok "old tree misbehaves ($o symptoms): the checks measure something" || bad "old tree passes"
    else
        bad "old kernel build"
    fi
fi
echo "OFSMNT: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
