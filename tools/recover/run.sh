#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/recover/run.sh -- r60 recovery onto a blank disk, with counter-proofs.
#
#   heavy bash tools/recover/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"
export OUT
trap 'rm -rf "$OUT"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' is not in $(basename "$1")"; }
nicht() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is in $(basename "$1")" || ok "$3"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }

lauf() {
    OUT="$OUT" ZWEITE_PLATTE="${ZWEITE_PLATTE:-}" \
        bash tools/install/oneshot.sh "$1" "$2" "${3:-}" "${4:-900}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

sum() { sha256sum < "$1" | cut -d' ' -f1; }

echo "== 1. build =="
PROGS="sh ls cat echo cp mv rm mkdir rmdir touch head tail wc grep sort uniq true false sleep ps kill uname date df mount umount install opk sync tar find du chmod id whoami backup recover shasum" \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 || {
        echo "  FAIL  build.sh"; tail -20 "$OUT/build.log"; exit 1; }
[ -f "$OUT/bin/recover" ] && ok "recover is built" || bad "recover is not built"

echo
echo "== 2. the backup medium (FAT32, second disk) and a backup of a data tree =="
head -c $((64 * 1024 * 1024)) /dev/zero > "$OUT/fatpart.img"
mkfs.vfat -F 32 -s 1 -n OSUMSTORE "$OUT/fatpart.img" > /dev/null 2>&1 && ok "mkfs.vfat" || bad "mkfs.vfat"
head -c $((80 * 1024 * 1024)) /dev/zero > "$OUT/store.img"
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$OUT/store.img" > /dev/null 2>&1 && ok "sfdisk" || bad "sfdisk"
dd if="$OUT/fatpart.img" of="$OUT/store.img" bs=512 seek=2048 conv=notrunc status=none
rm -f "$OUT/fatpart.img"
export ZWEITE_PLATTE="$OUT/store.img"

head -c $((256 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
rc=$(lauf save iso "mkdir /data;mkdir /data/sub;echo recover-marker-7 > /data/a.txt;echo deep-file-9 > /data/sub/b.txt;cp /bin/sh /data/sh.copy;shasum /bin/sh /data/sh.copy;mkdir /mnt/store;backup save /data /mnt/store snap1;backup list /mnt/store;exit" 900)
gleich "save run: exit code" "$rc" "21"
hat "$OUT/save.txt" "snap1" "the snapshot exists"
SHA_ORIG=$(grep -aoE '^[0-9a-f]{64}  /bin/sh' "$OUT/save.txt" | head -1 | cut -c1-64)
[ ${#SHA_ORIG} -eq 64 ] && ok "reference hash of /bin/sh taken" || bad "no reference hash"
cp -f "$OUT/store.img" "$OUT/store-good.img"

echo
echo "== 3. counter-proof: a damaged backup never touches the target =="
head -c $((256 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
BEFORE=$(sum "$OUT/ziel.img")
PACKPATH=/store
mcopy -o -i "$OUT/store.img@@1048576" "::$PACKPATH/PACK" "$OUT/PACK.bin" 2>/dev/null && ok "pack file found on the medium" || bad "no pack file on the medium"
SZ=$(stat -c%s "$OUT/PACK.bin" 2>/dev/null || echo 0)
python3 -I - "$OUT/PACK.bin" $((SZ/2)) <<'PY'
import sys
p, off = sys.argv[1], int(sys.argv[2])
b = bytearray(open(p, 'rb').read())
b[off] ^= 0x01
open(p, 'wb').write(b)
PY
mcopy -o -i "$OUT/store.img@@1048576" "$OUT/PACK.bin" "::$PACKPATH/PACK" && ok "one octet in the pack flipped on the medium"
rc=$(lauf bad iso "mkdir /mnt/store;recover /dev/hda /mnt/store snap1 --ja --into /data;exit" 900)
hat "$OUT/bad.txt" "recover: backup verify failed, target untouched" "damaged backup is refused before anything is written"
nicht "$OUT/bad.txt" "install: gpt ok" "the installer never ran"
gleich "target disk after the refused run" "$(sum "$OUT/ziel.img")" "$BEFORE"
cp -f "$OUT/store-good.img" "$OUT/store.img"

echo
echo "== 4. counter-proof: a dry run writes nothing =="
rc=$(lauf dry iso "mkdir /mnt/store;recover /dev/hda /mnt/store snap1;exit" 900)
hat "$OUT/dry.txt" "recover: dry run, nothing written" "dry run says so"
gleich "target disk after the dry run" "$(sum "$OUT/ziel.img")" "$BEFORE"
rc=$(lauf prot iso "mkdir /mnt/store;recover /dev/ram0 /mnt/store snap1 --ja;exit" 900)
hat "$OUT/prot.txt" "recover: refused, boot or ram device" "the boot ram device is refused"

echo
echo "== 5. recovery onto the blank disk =="
rc=$(lauf rec iso "ls /data;mkdir /mnt/store;recover /dev/hda /mnt/store snap1 --ja --into /data;exit" 1500)
gleich "recover run: exit code" "$rc" "21"
hat "$OUT/rec.txt" "recover: backup verified" "backup verified first"
hat "$OUT/rec.txt" "install: fertig" "system installed on the blank disk"
hat "$OUT/rec.txt" "recover: restored" "backup restored into the new root"
hat "$OUT/rec.txt" "recover: done" "recover finished"
nicht "$OUT/rec.txt" "recover: restore failed" "no restore failure"

echo
echo "== 6. boot FROM the recovered disk =="
rc=$(lauf boot platte "cat /data/a.txt;cat /data/sub/b.txt;shasum /data/sh.copy;ls /data;uname -a;exit" 600)
gleich "boot run: exit code" "$rc" "21"
hat "$OUT/boot.txt" "recover-marker-7" "file restored with its content"
hat "$OUT/boot.txt" "deep-file-9" "nested file restored"
SHA_NEW=$(grep -aoE '^[0-9a-f]{64}  /data/sh.copy' "$OUT/boot.txt" | head -1 | cut -c1-64)
gleich "restored binary hash equals the original" "$SHA_NEW" "$SHA_ORIG"

echo
echo "=================================================================="
echo "$pass green, $fail red"
[ "$fail" -eq 0 ] || exit 1
