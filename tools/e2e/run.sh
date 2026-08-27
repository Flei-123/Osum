#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/e2e/run.sh -- ONE RUN THAT SHOWS THE PIECES FIT TOGETHER.
#
# Every round has its own acceptance and each proves its own piece. This
# one proves nothing new, and that is the point: it walks the way a
# person walks, in order, on ONE disk, and every step has to work on
# what the step before it left behind.
#
#   1. install onto an empty virtual disk (the ISO situation: the root
#      filesystem arrives as a boot module, the disk is /dev/hda)
#   2. START FROM THAT DISK, through OVMF and the EFI partition the
#      installer wrote -- no -kernel and no module
#   3. a restart: what was written is still there
#   4. a package installed with `opk`, and it runs
#   5. an update: a second generation
#   6. one generation back, and the old version runs again
#   7. a backup onto a SECOND medium, and the HOST looks at that medium
#      afterwards with mdir -- not the machine that wrote it
#   8. one file fetched back out of that backup
#
# TWO THINGS THIS RUN HAD TO WORK AROUND, both worth knowing:
#
#   * The image is FILESYSTEM VERSION 3. In version 2 a file holds
#     8 + 64 + 4096 blocks of 512 octets = 2,134,016 -- and the kernel
#     is bigger than that after twenty rounds (main's was 1,703,304 and
#     fitted). Version 3 (round OFS3) has the triple indirect pointer.
#     `tools/install/build.sh` therefore builds version 3 by default now;
#     FSVER=2 reproduces the old behaviour, and then mkfs.py refuses.
#   * The second medium is FAT32 and not OFS. OFS CANNOT BE MOUNTED
#     TWICE: `kernel/vfs.fi` mount_at ends in `r = ofs.node_root(state)`
#     for FS_OFS, which is the root filesystem, whatever device was
#     named. `mount /dev/hdb /m ofs` therefore returns 0 and gives you a
#     second view of the disk you are already running from -- measured,
#     not read. A backup written there would be on the same disk.
#
# Usage:  bash tools/e2e/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${OUT:-/root/mergerun/e2e}
mkdir -p "$OUT"
export OUT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' is not in $(basename "$1")"; }
gleich() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }

lauf() { # name how script [limit]
    OUT="$OUT" ZWEITE_PLATTE="${ZWEITE_PLATTE:-}" \
        bash tools/install/oneshot.sh "$1" "$2" "${3:-}" "${4:-900}" > /dev/null 2>&1
    sed -i -e 's/\x1b\[[0-9;=]*[a-zA-Z]//g' "$OUT/$1.txt" 2>/dev/null
    cat "$OUT/$1.rc" 2>/dev/null
}

echo "== 1. the kernel, the programs, two signed package sources =="
PROGS=${PROGS:-"sh ls cat echo cp mv rm mkdir rmdir touch head tail wc grep sort uniq true false sleep ps kill uname date df mount umount install opk sync tar find du chmod id whoami backup"} \
    bash tools/install/build.sh "$OUT" > "$OUT/build.log" 2>&1 || {
        echo "  FAIL  build.sh"; tail -20 "$OUT/build.log"; exit 1; }
grep -aE '^   (kern|programme|pakete|quelle)' "$OUT/build.log" | sed 's/^/        /'
K=$(stat -c%s "$OUT/k.mb")
ok "the kernel is built ($K octets)"
echo "        version 2 would hold $(( (8 + 64 + 4096) * 512 )) octets in one file -- this kernel does not fit in one"

echo
echo "== 2. install onto an empty disk =="
rm -f "$OUT/ziel.img"
head -c $((256 * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
rc=$(lauf inst iso "install /dev/hda --ja;exit" 900)
gleich "installer exit code" "$rc" "21"
hat "$OUT/inst.txt" "install: gpt ok" "the GPT is written"
hat "$OUT/inst.txt" "install: fat32 ok" "the EFI partition carries FAT32"
hat "$OUT/inst.txt" "install: fertig" "the installer says it is done"
grep -aE '^install: (kopiert|gewachsen)' "$OUT/inst.txt" | sed 's/^/        /'

echo
echo "== 3. start FROM the disk, through OVMF, and write something =="
rc=$(lauf boot1 platte "uname -a;echo e2e-was-here > /etc/e2e.txt;cat /etc/e2e.txt;exit" 600)
gleich "first boot from the disk: exit code" "$rc" "21"
hat "$OUT/boot1.txt" "e2e-was-here" "the file is readable in the same run"
rc=$(lauf boot2 platte "cat /etc/e2e.txt;exit" 600)
gleich "second boot: exit code" "$rc" "21"
hat "$OUT/boot2.txt" "e2e-was-here" "and it is still there after a restart"

echo
echo "== 4. a package, installed on the machine itself =="
rc=$(lauf pak1 platte "opk installieren /quelle1/hallo-1.opk;opk liste;/apps/hallo.osp/start;exit" 600)
gleich "opk installieren: exit code" "$rc" "21"
hat "$OUT/pak1.txt" "opk: installiert hallo" "opk says it installed the package"
hat "$OUT/pak1.txt" "paket-hallo fassung 1" "and the installed program RUNS out of /apps"

echo
echo "== 5. an update, which is a second generation =="
rc=$(lauf pak2 platte "opk aktualisieren hallo --quelle /quelle2;opk generationen;exit" 600)
hat "$OUT/pak2.txt" "opk: installiert hallo" "the update is taken"
hat "$OUT/pak2.txt" "generation 1" "there are two generations now"
grep -aE '^generation ' "$OUT/pak2.txt" | sed 's/^/        /'
rc=$(lauf pak3 platte "/apps/hallo.osp/start;exit" 600)
hat "$OUT/pak3.txt" "paket-hallo fassung 2" "after a restart the NEW version runs"

echo
echo "== 6. one generation back =="
rc=$(lauf pak4 platte "opk zurueck 0;/apps/hallo.osp/start;exit" 600)
hat "$OUT/pak4.txt" "opk: zurueck auf 0" "opk goes back one generation"
hat "$OUT/pak4.txt" "paket-hallo fassung 1" "and the OLD version runs again"

echo
echo "== 7. a backup onto a SECOND medium =="
# 64 MiB of FAT32 in an MBR partition -- a USB stick, in other words.
# The kernel mounts the first FAT partition it finds at /mnt, so this
# run does NOT call mount: it writes to /mnt and then the HOST checks
# with mdir WHICH disk the octets landed on.
rm -f "$OUT/fatpart.img" "$OUT/store.img"
head -c $((64 * 1024 * 1024)) /dev/zero > "$OUT/fatpart.img"
mkfs.vfat -F 32 -s 1 -n OSUMSTORE "$OUT/fatpart.img" > /dev/null 2>&1 \
    && ok "mkfs.vfat built the second medium (64 MiB)" || bad "mkfs.vfat failed"
head -c $((80 * 1024 * 1024)) /dev/zero > "$OUT/store.img"
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$OUT/store.img" > /dev/null 2>&1 \
    && ok "sfdisk wrote an MBR table (type 0x0C)" || bad "sfdisk failed"
dd if="$OUT/fatpart.img" of="$OUT/store.img" bs=512 seek=2048 conv=notrunc status=none
cp -f "$OUT/store.img" "$OUT/store-vorher.img"

export ZWEITE_PLATTE="$OUT/store.img"
rc=$(lauf sich platte "mount;mkdir /mnt/store;backup save /etc /mnt/store etc1;backup list /mnt/store;exit" 900)
gleich "backup run: exit code" "$rc" "21"
hat "$OUT/sich.txt" "etc1" "the store names the snapshot back"
if cmp -s "$OUT/store.img" "$OUT/store-vorher.img"; then
    bad "the second medium is unchanged -- nothing was written onto it"
else
    ok "the second medium changed: something really was written onto it"
fi
mdir -i "$OUT/store.img@@1048576" ::/store > "$OUT/mdir-store.txt" 2>&1
sed 's/^/        /' "$OUT/mdir-store.txt" | head -12
hat "$OUT/mdir-store.txt" "PACK" "the HOST sees the backup's pack file on that medium"
hat "$OUT/mdir-store.txt" "INDEX" "and its index"
hat "$OUT/mdir-store.txt" "S-ETC1" "and the snapshot named etc1"

echo
echo "== 8. one file back out of the backup =="
rc=$(lauf hole platte "backup get /mnt/store etc1 /e2e.txt /zurueck.txt;cat /zurueck.txt;exit" 900)
gleich "restore run: exit code" "$rc" "21"
hat "$OUT/hole.txt" "e2e-was-here" "the file that came back out of the backup has its content"

echo
echo "=================================================================="
echo "$pass green, $fail red"
[ "$fail" -eq 0 ] || exit 1
