#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
FIRNC=vendor/firn/bin/firnc

echo "== 1. host: gptw + ofsfmt against independent parsers =="
python3 tools/disks/mkdisk.py "$D" >/dev/null
mkdir -p "$D/w"; cp "$D/empty.img" "$D/w/disk.img"
if "$FIRNC" -o "$D/wunit" tools/disks/wunit.fi > "$D/cc.log" 2>&1 && ( cd "$D/w" && "$D/wunit" > out.txt 2>&1 ); then
    python3 tools/disks/wcheck.py "$D/w" > "$D/wc.txt" 2>&1; rc=$?
    cat "$D/wc.txt" | grep -a "FAIL" | head
    [ "$rc" -eq 0 ] && ok "host: $(tail -1 "$D/wc.txt")" || bad "host: $(tail -1 "$D/wc.txt")"
    grep -aq '^create-overlap rc=3' "$D/w/out.txt" && grep -aq '^create-range rc=2' "$D/w/out.txt" && grep -aq '^delete-bad rc=8' "$D/w/out.txt" \
        && ok "host: overlap, out-of-range and bad index are refused" || bad "host: refusals missing"
else
    bad "wunit does not build or run"; head -10 "$D/cc.log"
fi

echo "== 2. VM: diskctl writes on a disposable disk, refuses the system disk =="
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then echo "   (qemu missing)"; echo "DISKS-WRITE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit; fi
PROGS="diskctl sh echo ls cat mount"
bash tools/build-kernel.sh "$D/k0.mb" > "$D/k0.log" 2>&1 || { bad "kernel build"; echo "DISKS-WRITE: $pass passed, $fail failed"; exit 1; }
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/bin.log" 2>&1 || { bad "programs build"; head -5 "$D/bin.log"; echo "DISKS-WRITE: $pass passed, $fail failed"; exit 1; }
MK=""; for p in $PROGS; do MK="$MK /bin/$p=$D/bin/$p.elf"; done
python3 tools/osum/mkfs.py build "$D/root.img" 4096 /bin/ /dev/ /mnt/ $MK > "$D/mkfs.log" 2>&1 || { bad "mkfs"; exit 1; }
cp "$D/root.img" "$D/hda.img"; dd if=/dev/zero of="$D/hdb.img" bs=1M count=0 seek=16 2>/dev/null
tailsum() { tail -c 17408 "$D/hda.img" | sha256sum | cut -d' ' -f1; }
H=$(tailsum)
C="--confirm=/dev/hdb"
run_vm() {
    timeout 150 qemu-system-x86_64 -accel kvm -kernel "$D/k0.mb" -m 256 -append "osum nokbd vfs nopart script=$2" \
        -serial "file:$D/$1.txt" -display none -no-reboot \
        -drive "file=$D/hda.img,format=raw,if=ide,index=0" -drive "file=$D/hdb.img,format=raw,if=ide,index=1" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}
run_vm a "diskctl init /dev/hdb $C;diskctl create /dev/hdb auto 8192 ofs data1 $C;diskctl create /dev/hdb auto 4096 efi boot $C;diskctl format /dev/hdb 1 $C --time=1700000000;diskctl list;diskctl delete /dev/hdb 2;diskctl delete /dev/hdb 2 --confirm=/dev/hda;diskctl init /dev/hdb $C;diskctl create /dev/hdb 2048 100 basic x $C;diskctl init /dev/hda --confirm=/dev/hda;diskctl create /dev/hda auto 100 ofs x --confirm=/dev/hda;diskctl delete /dev/hda 1 --confirm=/dev/hda;diskctl format /dev/hda 1 --confirm=/dev/hda;exit"
S="$D/a.txt"
grep -aq '^done: init' "$S" && grep -aq '^verify: table=gpt partitions=0' "$S" && ok "init writes a GPT and the verify line reads it back" || bad "init on hdb"
grep -aq '^verify: table=gpt partitions=2' "$S" && ok "two partitions created" || bad "create"
grep -aq '^done: format' "$S" && ok "format of partition 1 done" || bad "format"
grep -aq '^  1 start=2048 sectors=8192 kind=ofs name=data1' "$S" && grep -aq '^  2 start=10240 sectors=4096 kind=efi name=boot' "$S" && ok "diskctl list shows the new partitions" || bad "list after writes"
[ "$(grep -ac '^needs confirmation: repeat with --confirm=/dev/hdb' "$S")" -ge 2 ] && ok "counter-proof: no confirm and a wrong confirm change nothing" || bad "confirm counter-proof"
grep -aq '^refused: disk already has a partition table' "$S" && ok "counter-proof: init on a disk with a table is refused" || bad "has-table refusal"
grep -aq '^failed: overlaps a partition' "$S" && ok "counter-proof: overlapping create is refused by the library" || bad "overlap refusal"
[ "$(grep -ac '^refused: system disk' "$S")" -ge 4 ] && ok "counter-proof: init, create, delete, format on the system disk are all refused" || bad "system disk refusals: $(grep -ac '^refused: system disk' "$S")"
[ "$(tailsum)" = "$H" ] && ok "the sectors a GPT would use at the end of the system disk are untouched" || bad "THE SYSTEM DISK TAIL CHANGED"
grep -aq '^disk /dev/hda sectors=4096 table=none' "$S" && ok "the system disk still has no partition table" || bad "system disk table changed"
python3 tools/disks/wcheck.py vm "$D/hdb.img" "[(2048, 8192, 'ofs', 'data1'), (10240, 4096, 'efi', 'boot')]" 8192 > "$D/v.txt" 2>&1
grep -a FAIL "$D/v.txt" | head -4
[ "$(tail -1 "$D/v.txt" | grep -c ' 0 failed')" = 1 ] && ok "host check of the VM-written disk: $(tail -1 "$D/v.txt")" || bad "host check of the VM-written disk"
run_vm b "diskctl delete /dev/hdb 2 $C;diskctl list;exit"
grep -aq '^done: delete' "$D/b.txt" && grep -aq '^verify: table=gpt partitions=1' "$D/b.txt" && ok "delete of partition 2 done" || bad "delete"
echo "DISKS-WRITE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
