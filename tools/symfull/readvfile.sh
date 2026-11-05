#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/lib/tmpdir.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC="$ROOT/vendor/firn/bin/firnc"
SIZE=44900
W=$(mktemp -d)
osum_tmp_guard "${1:-}" "$W"
trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mkdir -p "$W/old"
tar --exclude=.git -cf - . | tar -xf - -C "$W/old"
sed -i 's/return kind == file.K_FILE || kind == file.K_VFILE/return kind == file.K_FILE/' "$W/old/kernel/sys/sysfd.fi"
cmp -s kernel/sys/sysfd.fi "$W/old/kernel/sys/sysfd.fi" && { bad "control kernel identical to the fixed one"; exit 1; }
bash tools/build-kernel.sh "$W/new.mb" --stufe 0 > "$W/build-new.log" 2>&1 || { tail -5 "$W/build-new.log"; bad "kernel build"; exit 1; }
(cd "$W/old" && bash tools/build-kernel.sh "$W/old.mb" --stufe 0 > "$W/build-old.log" 2>&1) || { tail -5 "$W/build-old.log"; bad "control kernel build"; exit 1; }

as --64 -o "$W/crt.o" kernel/user/crt.s
mkdir -p "$W/user"
cp -r kernel/user/. "$W/user/"
cp tools/symfull/readvfile.fi "$W/user/"
SPEC=""
for p in sh cat echo shasum mount umount readvfile; do
    (cd "$W/user" && "$FIRNC" "$p.fi" -o "$W/$p.o") > "$W/e$p" 2>&1 || { head -4 "$W/e$p"; bad "$p compile"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" || exit 1
    strip --strip-all "$W/$p.elf"
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done

python3 -I - "$W/big.bin" "$SIZE" "$W/expect.txt" <<'PY'
import sys
n = int(sys.argv[2]); out = bytearray(); x = 4242
while len(out) < n:
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    out += x.to_bytes(4, "little")
data = bytes(out[:n])
open(sys.argv[1], "wb").write(data)
open(sys.argv[3], "w").write("readone: bytes = %d\nreadone: sum = %d\n" % (n, sum(data)))
PY
SHA=$(sha256sum "$W/big.bin" | cut -d' ' -f1)

dd if=/dev/null of="$W/fat.fs" bs=1M seek=40 2>/dev/null
mkfs.fat -F 32 -s 1 "$W/fat.fs" > /dev/null 2>&1 || { bad "mkfs.fat"; exit 1; }
mcopy -i "$W/fat.fs" "$W/big.bin" ::/big.bin || { bad "mcopy"; exit 1; }
dd if=/dev/null of="$W/disk.img" bs=1M seek=42 2>/dev/null
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$W/disk.img" > /dev/null 2>&1
dd if="$W/fat.fs" of="$W/disk.img" bs=512 seek=2048 conv=notrunc status=none

cat > "$W/s.sh" <<'SEOF'
echo "unlock hdb" > /dev/wlock
umount /mnt
mount /dev/hdb1 /mnt vfat
echo "@@mount-rc=$?"
readvfile /mnt/big.bin
shasum /mnt/big.bin
umount /mnt
echo @@end
SEOF
bash tools/mkfsfi/mkfs.sh build "$W/root.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $SPEC "/t/s.sh=$W/s.sh" > "$W/mkfs.log" 2>&1 || { tail -3 "$W/mkfs.log"; bad "mkfs root"; exit 1; }

run_os() {
    local k=$1 out=$2 acc=""
    [ "${OSUM_QEMU_ACCEL:-}" = kvm ] && acc="-cpu host"
    timeout 300 $QEMU_X86 $acc -kernel "$k" -m 512 \
        -append "osum nokbd vfs script=sh /t/s.sh;exit" \
        -serial "file:$out.raw" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        -drive "file=$W/root.img,format=raw,if=ide,index=0" \
        -drive "file=$W/disk.img,format=raw,if=ide,index=1" > /dev/null 2>&1
    local rc=$?
    tr -d '\r\000' < "$out.raw" > "$out"
    return $rc
}

echo "== A. fixed kernel: one read of $SIZE octets on a mounted FAT32 file =="
run_os "$W/new.mb" "$W/new.txt"; rc=$?
[ "$rc" = 21 ] && ok "A OS finished (rc 21)" || bad "A OS rc=$rc"
grep -aq '@@mount-rc=0' "$W/new.txt" && ok "A FAT32 mounted" || bad "A mount failed: $(grep -a '@@' "$W/new.txt" | tr '\n' ' ')"
grep -aq "^readone: bytes = $SIZE\$" "$W/new.txt" && ok "A one read returned all $SIZE octets" || bad "A short read: $(grep -a 'readone: bytes' "$W/new.txt" | head -1)"
exp_sum=$(sed -n 2p "$W/expect.txt")
grep -aqxF "$exp_sum" "$W/new.txt" && ok "A byte sum of the read data matches" || bad "A byte sum differs"
grep -aq "^$SHA  /mnt/big.bin" "$W/new.txt" && ok "A shasum of the file matches" || bad "A shasum differs"

echo "== B. control kernel (K_VFILE loop removed): read is cut at one block =="
run_os "$W/old.mb" "$W/old.txt"; rc=$?
grep -aq '@@mount-rc=0' "$W/old.txt" && ok "B FAT32 mounted" || bad "B mount failed"
grep -aq "^readone: bytes = 4096\$" "$W/old.txt" && ok "B control cut at 4096 octets (counter-proof active)" || bad "B control not cut: $(grep -a 'readone: bytes' "$W/old.txt" | head -1)"
echo
if [ -n "${READVFILE_OUT:-}" ]; then mkdir -p "$READVFILE_OUT"; cp "$W"/*.txt "$READVFILE_OUT/"; fi
echo "READVFILE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
