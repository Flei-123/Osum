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

echo "== 5. encrypted root (cryptboot header, XTS-AES-256, Argon2id) =="
CRYPTPY=${OSUM_KRYPTO_PY:-/root/.krypto-venv/bin/python}
[ -x "$CRYPTPY" ] || CRYPTPY=python3
if ! "$CRYPTPY" -c "import argon2, cryptography" 2>/dev/null; then
    bad "argon2-cffi + cryptography missing for $CRYPTPY"
else
    PW=geheim123
    "$CRYPTPY" tools/fsck/cryptdisk.py build "$TMPD/ofs.img" "$TMPD/crypt.raw" "$PW" >/dev/null || bad "cryptdisk build"
    python3 tools/fsck/gptdisk.py "$TMPD/crypt.raw" "$TMPD/crypt.gpt" ofs >/dev/null || bad "gptdisk crypt"
    "$CRYPTPY" tools/fsck/cryptdisk.py leak "$TMPD/ofs.img" "$TMPD/leak.img" >/dev/null || bad "cryptdisk leak"
    "$CRYPTPY" tools/fsck/cryptdisk.py build "$TMPD/leak.img" "$TMPD/leak.raw" "$PW" >/dev/null || bad "cryptdisk build leak"
    python3 tools/fsck/gptdisk.py "$TMPD/leak.raw" "$TMPD/leak.gpt" ofs >/dev/null || bad "gptdisk leak"
    "$CRYPTPY" tools/fsck/cryptdisk.py corrupt "$TMPD/crypt.raw" "$TMPD/crypt.badsb" 0 || bad "cryptdisk corrupt"
    python3 tools/fsck/gptdisk.py "$TMPD/crypt.badsb" "$TMPD/crypt.badsb.gpt" ofs >/dev/null || bad "gptdisk badsb"

    run_fsck "$TMPD/crypt.gpt" "fsck --check-only --crypt $PW /dev/hdb" "$TMPD/g.txt"
    expect "crypt GPT: crypt" "$(val "$TMPD/g.txt" crypt)" 1
    expect "crypt GPT: crypt_open" "$(val "$TMPD/g.txt" crypt_open)" 1
    expect "crypt GPT: crypt_slot" "$(val "$TMPD/g.txt" crypt_slot)" 0
    expect "crypt GPT: partition_start" "$(val "$TMPD/g.txt" partition_start)" 2048
    expect "crypt GPT: magic" "$(val "$TMPD/g.txt" magic)" 1
    expect "crypt GPT: errors" "$(val "$TMPD/g.txt" errors)" 0
    expect "crypt GPT: blocks" "$(val "$TMPD/g.txt" blocks)" 16384
    expect_gt "crypt GPT: files" "$(val "$TMPD/g.txt" files)" 0
    cmp -s "$TMPD/crypt.gpt" "$TMPD/target.img" && ok "crypt check-only left the disk byte-identical" || bad "crypt check-only changed the disk"

    run_fsck "$TMPD/crypt.raw" "fsck --check-only --crypt $PW /dev/hdb" "$TMPD/h.txt"
    expect "crypt whole disk: crypt_open" "$(val "$TMPD/h.txt" crypt_open)" 1
    expect "crypt whole disk: magic" "$(val "$TMPD/h.txt" magic)" 1
    expect "crypt whole disk: errors" "$(val "$TMPD/h.txt" errors)" 0

    run_fsck "$TMPD/crypt.gpt" "fsck --check-only --crypt wrongpass /dev/hdb" "$TMPD/i.txt"
    expect "wrong passphrase: crypt_open" "$(val "$TMPD/i.txt" crypt_open)" 0
    expect "wrong passphrase: magic" "$(val "$TMPD/i.txt" magic)" 0
    expect_gt "wrong passphrase: errors" "$(val "$TMPD/i.txt" errors)" 0
    cmp -s "$TMPD/crypt.gpt" "$TMPD/target.img" && ok "wrong passphrase left the disk byte-identical" || bad "wrong passphrase changed the disk"

    run_fsck "$TMPD/crypt.gpt" "fsck --check-only /dev/hdb" "$TMPD/j.txt"
    expect "no passphrase: crypt" "$(val "$TMPD/j.txt" crypt)" 1
    expect "no passphrase: crypt_open" "$(val "$TMPD/j.txt" crypt_open)" 0
    expect_gt "no passphrase: errors" "$(val "$TMPD/j.txt" errors)" 0

    run_fsck "$TMPD/crypt.badsb.gpt" "fsck --check-only --crypt $PW /dev/hdb" "$TMPD/k.txt"
    expect "crypt, damaged superblock: crypt_open" "$(val "$TMPD/k.txt" crypt_open)" 1
    expect "crypt, damaged superblock: magic" "$(val "$TMPD/k.txt" magic)" 0
    expect_gt "crypt, damaged superblock: errors" "$(val "$TMPD/k.txt" errors)" 0

    run_fsck "$TMPD/leak.gpt" "fsck --check-only --crypt $PW /dev/hdb" "$TMPD/l.txt"
    expect "crypt, leaked block: lost" "$(val "$TMPD/l.txt" lost)" 1
    expect_gt "crypt, leaked block: errors" "$(val "$TMPD/l.txt" errors)" 0
    cmp -s "$TMPD/leak.gpt" "$TMPD/target.img" && ok "crypt leaked-block check-only left the disk byte-identical" || bad "crypt leaked-block check-only changed the disk"

    run_fsck "$TMPD/leak.gpt" "fsck --crypt $PW /dev/hdb" "$TMPD/m.txt"
    expect "crypt repair: fixed" "$(val "$TMPD/m.txt" fixed)" 1
    cp --sparse=always "$TMPD/target.img" "$TMPD/repaired.img"
    run_fsck "$TMPD/repaired.img" "fsck --check-only --crypt $PW /dev/hdb" "$TMPD/n.txt"
    expect "crypt after repair: errors" "$(val "$TMPD/n.txt" errors)" 0
    expect "crypt after repair: lost" "$(val "$TMPD/n.txt" lost)" 0
    "$CRYPTPY" -I - "$TMPD/leak.gpt" "$TMPD/repaired.img" <<'PY' && ok "repair rewrote exactly one ciphertext sector, no plaintext on the disk" || bad "repair result on disk is wrong"
import sys
before = open(sys.argv[1], "rb").read()
after = open(sys.argv[2], "rb").read()
assert len(before) == len(after)
changed = [i for i in range(0, len(before), 512) if before[i:i + 512] != after[i:i + 512]]
assert len(changed) == 1, changed
part = after[2048 * 512:]
assert part[:9] == b"OSUMCRYPT"
assert part[8 * 512:8 * 512 + 8] != bytes([0x53, 0x46, 0x4F, 0x2D, 0x4D, 0x55, 0x53, 0x4F])
PY

    if [ -f "$TMPD/fsckold.elf" ]; then
        run_fsck "$TMPD/crypt.gpt" "fsckold /dev/hdb" "$TMPD/o.txt"
        expect "old fsck on encrypted disk: magic" "$(val "$TMPD/o.txt" magic)" 0
    fi
fi

echo
echo "FSCK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
