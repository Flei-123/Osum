#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."

export FIRNLIB="$(pwd)/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
ULD=kernel/user/user.ld
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
val() { tr -d '\000' < "$1" 2>/dev/null | grep -a "^fsck: $2 = " | head -1 | sed 's/.* = //'; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: got '$2', want '$3'"; fi
}
expect_gt() {
    if [ -n "$2" ] && [ "$2" -gt "$3" ] 2>/dev/null; then ok "$1: $2"; else bad "$1: got '$2', want > $3"; fi
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "fetch-firnc.sh failed"; exit 1; }
[ -x "$FIRNC" ] || { echo "firnc missing: $FIRNC"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "FSCK: skipped, qemu-system-x86_64 missing"
    exit 0
fi

echo "== 1. build =="
bash tools/build-kernel.sh "$TMPD/k.mb" >"$TMPD/build.txt" 2>&1 \
    && ok "kernel built" \
    || { bad "kernel build failed"; tail -8 "$TMPD/build.txt" | sed 's/^/        /';
         echo "FSCK: $pass passed, $((fail+1)) failed"; exit 1; }

SRC="$TMPD/src"
mkdir -p "$SRC"
cp kernel/user/*.fi "$SRC/"
PROGS="sh echo cat ls fsck"
if [ -n "${FSCK_OLD_REF:-}" ] && git show "$FSCK_OLD_REF:kernel/user/fsck.fi" > "$SRC/fsckold.fi" 2>/dev/null; then
    PROGS="$PROGS fsckold"
fi
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s"
for p in $PROGS; do
    "$FIRNC" "$SRC/$p.fi" -o "$TMPD/$p.o" >"$TMPD/e$p" 2>&1 \
        || { bad "$p.fi does not compile"; head -6 "$TMPD/e$p" | sed 's/^/        /'; continue; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F0.u_start" \
        -o "$TMPD/$p.elf" "$TMPD/crt.o" "$TMPD/$p.o" 2>/dev/null
    strip --strip-all "$TMPD/$p.elf" 2>/dev/null
done
ok "programs built: $PROGS"

SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$TMPD/$p.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" 65536 --v3 --inodes=512 \
    --time=1780000000 $SPEC >/dev/null 2>&1 || bad "mkfs root"
echo hello > "$TMPD/hello.txt"
python3 tools/osum/mkfs.py build "$TMPD/ofs.img" 16384 --v3 --inodes=128 \
    --time=1780000000 /etc/ /hello.txt="$TMPD/hello.txt" >/dev/null 2>&1 || bad "mkfs data"
python3 tools/fsck/gptdisk.py "$TMPD/ofs.img" "$TMPD/gpt.img" ofs > "$TMPD/gpt.txt" || bad "gptdisk ofs"
python3 tools/fsck/gptdisk.py "$TMPD/ofs.img" "$TMPD/basic.img" basic >/dev/null || bad "gptdisk basic"
cp "$TMPD/ofs.img" "$TMPD/raw.img"
sed 's/^/        /' "$TMPD/gpt.txt"

run_fsck() {
    cp --sparse=always "$1" "$TMPD/target.img"
    cp --sparse=always "$TMPD/root.img" "$TMPD/rootrun.img"
    timeout 300 qemu-system-x86_64 -accel tcg -kernel "$TMPD/k.mb" -m 512 \
        -append "osum vfs nokbd nowlock script=$2;exit" \
        -serial "file:$3" -display none -no-reboot \
        -drive "file=$TMPD/rootrun.img,format=raw,if=ide,index=0" \
        -drive "file=$TMPD/target.img,format=raw,if=ide,index=1" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    sleep 3
}

echo "== 2. GPT disk, OFS in partition 2 =="
run_fsck "$TMPD/gpt.img" "fsck --check-only /dev/hdb" "$TMPD/a.txt"
expect "check-only: magic" "$(val "$TMPD/a.txt" magic)" 1
expect "check-only: partition_start" "$(val "$TMPD/a.txt" partition_start)" 2048
expect "check-only: errors" "$(val "$TMPD/a.txt" errors)" 0
expect_gt "check-only: files" "$(val "$TMPD/a.txt" files)" 0
expect "check-only: blocks" "$(val "$TMPD/a.txt" blocks)" 16384
cmp -s "$TMPD/gpt.img" "$TMPD/target.img" && ok "check-only left the disk byte-identical" || bad "check-only changed the disk"

run_fsck "$TMPD/gpt.img" "fsck /dev/hdb" "$TMPD/a2.txt"
expect "plain run: errors" "$(val "$TMPD/a2.txt" errors)" 0

echo "== 3. raw OFS disk (no table) =="
run_fsck "$TMPD/raw.img" "fsck --check-only /dev/hdb" "$TMPD/b.txt"
expect "raw: magic" "$(val "$TMPD/b.txt" magic)" 1
expect "raw: partition_start" "$(val "$TMPD/b.txt" partition_start)" 0
expect "raw: errors" "$(val "$TMPD/b.txt" errors)" 0

echo "== 4. counter-probes =="
if [ -f "$TMPD/fsckold.elf" ]; then
    run_fsck "$TMPD/gpt.img" "fsckold /dev/hdb" "$TMPD/c.txt"
    expect "old fsck on GPT disk: magic" "$(tr -d '\000' < "$TMPD/c.txt" | grep -a '^fsck: magic = ' | head -1 | sed 's/.* = //')" 0
else
    echo "  --    old fsck counter-probe skipped (set FSCK_OLD_REF)"
fi

run_fsck "$TMPD/basic.img" "fsck --check-only /dev/hdb" "$TMPD/d.txt"
expect "partition without OFS type: magic" "$(val "$TMPD/d.txt" magic)" 0
expect_gt "partition without OFS type: errors" "$(val "$TMPD/d.txt" errors)" 0

python3 -I - "$TMPD/gpt.img" "$TMPD/badmagic.img" "$TMPD/badgeom.img" <<'PY'
import struct, sys
src, bad_magic, bad_geom = sys.argv[1:4]
data = bytearray(open(src, "rb").read())
off = 2048 * 512
magic = bytearray(data)
magic[off:off + 8] = b"\0" * 8
open(bad_magic, "wb").write(magic)
geom = bytearray(data)
geom[off + 40:off + 48] = struct.pack("<Q", 0)
open(bad_geom, "wb").write(geom)
PY
run_fsck "$TMPD/badmagic.img" "fsck --check-only /dev/hdb" "$TMPD/e.txt"
expect "broken superblock magic: magic" "$(val "$TMPD/e.txt" magic)" 0
expect_gt "broken superblock magic: errors" "$(val "$TMPD/e.txt" errors)" 0
expect "broken superblock magic: partition found" "$(val "$TMPD/e.txt" partition_start)" 2048
run_fsck "$TMPD/badgeom.img" "fsck --check-only /dev/hdb" "$TMPD/f.txt"
expect "broken superblock geometry: magic" "$(val "$TMPD/f.txt" magic)" 1
expect "broken superblock geometry: geom" "$(val "$TMPD/f.txt" geom)" 0
expect_gt "broken superblock geometry: errors" "$(val "$TMPD/f.txt" errors)" 0

echo
echo "FSCK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
