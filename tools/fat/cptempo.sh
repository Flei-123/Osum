#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fat/cptempo.sh -- r208: speed of a copy INSIDE one FAT32 volume.
#
# /bin/cp alternates 512-byte reads (source) and writes (target). With ONE
# chain cache per mount every block threw the position away and walked the
# chain from its start again: O(n^2) over PIO (3.5 KB/s measured on the
# Dell). This gate times the copy with the clock of the kernel and checks
# the result byte for byte.
#
#   bash tools/fat/cptempo.sh [KERNEL.mb]     (KERNEL skips the build)
# Prints:  cptempo: in-FAT copy KB/s = N   and   OFS->FAT KB/s = N
# Goal: in-FAT copy >= 100 KB/s and equal to the OFS->FAT speed within 2x.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
PROGS="sh cat echo ls cp rm mkdir wc shasum mount umount cptempo"
SIZE=${CPT_SIZE:-262144}
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
python3 -I - "$W/src.bin" "$SIZE" <<'PYEOF'
import sys, hashlib
n = int(sys.argv[2]); out = bytearray(); x = 12345
while len(out) < n:
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF
    out += x.to_bytes(4, "little")
open(sys.argv[1], "wb").write(bytes(out[:n]))
PYEOF
SHA=$(sha256sum "$W/src.bin" | cut -d' ' -f1)

# FAT32 with 512-byte clusters (worst case for the chain walk), 16 MiB
dd if=/dev/null of="$W/fat.fs" bs=1M seek=16 2>/dev/null
mkfs.fat -F 32 -s 1 "$W/fat.fs" >/dev/null 2>&1 || { echo "mkfs.fat failed"; exit 1; }
dd if=/dev/null of="$W/disk.img" bs=1M seek=18 2>/dev/null
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$W/disk.img" >/dev/null 2>&1
dd if="$W/fat.fs" of="$W/disk.img" bs=512 seek=2048 conv=notrunc status=none

cat > "$W/s.sh" <<'SEOF'
mount /dev/hdb1 /mnt vfat
echo "@@mount-rc=$?"
cptempo /src.bin /mnt/a.bin
echo @@ofs-to-fat
cptempo /mnt/a.bin /mnt/b.bin
echo @@in-fat
shasum /mnt/a.bin /mnt/b.bin
umount /mnt
echo @@end
SEOF
python3 tools/osum/mkfs.py build "$W/root.img" 20000 /bin/ /proc/ /dev/ /mnt/ /t/ $MKARGS \
    "/src.bin=$W/src.bin" "/t/s.sh=$W/s.sh" > "$W/mkfs.log" 2>&1 || { tail -3 "$W/mkfs.log"; exit 1; }
ACC=""; [ "$OSUM_QEMU_ACCEL" = kvm ] && ACC="-cpu host"
timeout ${CPT_TIMEOUT:-1200} $QEMU_X86 $ACC -kernel "$K" -m 512 \
    -append "osum nokbd vfs script=sh /t/s.sh;exit" \
    -serial "file:$W/out.txt" -display none -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
    -drive "file=$W/root.img,format=raw,if=ide,index=0" \
    -drive "file=$W/disk.img,format=raw,if=ide,index=1" >/dev/null 2>&1
rc=$?
tr -d '\r\000' < "$W/out.txt" > "$W/clean.txt"
[ "$rc" = 21 ] && ok "OS finished (rc 21)" || bad "OS rc=$rc (timeout?)"
grep -aq '^@@mount-rc=0' "$W/clean.txt" && ok "FAT32 mounted" || bad "mount failed"
ms1=$(sed -n '/^@@ofs-to-fat/q;p' "$W/clean.txt" | grep -a 'cptempo: ms' | head -1 | sed 's/.* = //')
ms2=$(sed -n '/^@@ofs-to-fat/,/^@@in-fat/p' "$W/clean.txt" | grep -a 'cptempo: ms' | head -1 | sed 's/.* = //')
kbs() { python3 -c "print(round($SIZE/1024/(max($1,1)/1000),1))"; }
echo "cptempo: size = $SIZE bytes, 512-byte clusters"
echo "cptempo: OFS -> FAT   ms = ${ms1:-?}   KB/s = $( [ -n "${ms1:-}" ] && kbs "$ms1" )"
echo "cptempo: in-FAT copy  ms = ${ms2:-?}   KB/s = $( [ -n "${ms2:-}" ] && kbs "$ms2" )"
n=$(grep -ac "^$SHA  /mnt/" "$W/clean.txt")
[ "$n" = 2 ] && ok "both copies have the SHA-256 of the source" || bad "copy content differs ($n of 2 sums equal)"
echo "CPTEMPO: $pass ok, $fail failed"
[ "$fail" = 0 ]
