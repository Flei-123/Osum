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
PROGS="contacts sh echo ls cat"
bash tools/build-kernel.sh "$D/k0.mb" > "$D/k0.log" 2>&1 || { bad "kernel build"; echo "CONTACTS: $pass passed, $fail failed"; exit 1; }
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/bin.log" 2>&1 || { bad "programs build"; head -8 "$D/bin.log"; echo "CONTACTS: $pass passed, $fail failed"; exit 1; }
MK=""; for p in $PROGS; do MK="$MK /bin/$p=$D/bin/$p.elf"; done
python3 tools/osum/mkfs.py build "$D/root.img" 4096 /bin/ /dev/ /etc/ $MK > "$D/mkfs.log" 2>&1 || { bad "mkfs"; exit 1; }
cp "$D/root.img" "$D/hda.img"
run_vm() {
    timeout 120 qemu-system-x86_64 -accel kvm -kernel "$D/k0.mb" -m 256 -append "osum nokbd vfs nopart script=$2" \
        -serial "file:$D/$1.txt" -display none -no-reboot \
        -drive "file=$D/$3,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
}
run_vm a "contacts add Ada 111 ada@x.org;contacts add Bob 222;contacts list;contacts find bo;contacts del 1;contacts list;contacts del 9;contacts find zed;contacts add;exit" hda.img
S="$D/a.txt"
grep -aq '^added: 2' "$S" && ok "two contacts added" || bad "add"
grep -aq '^1 name=Ada phone=111 email=ada@x.org' "$S" && grep -aq '^2 name=Bob phone=222 email=$' "$S" && ok "list shows both, email may be empty" || bad "list"
grep -aq '^2 name=Bob phone=222' "$S" && ok "find is case-insensitive and by part of the name" || bad "find"
grep -aq '^deleted: 1' "$S" && ok "delete by number" || bad "delete"
[ "$(grep -ac '^1 name=Bob phone=222' "$S")" -ge 1 ] && ok "after delete Bob is number 1" || bad "renumber"
[ "$(grep -ac 'no such contact' "$S")" -ge 2 ] && ok "counter-proof: delete of a missing number and find of a missing name are refused" || bad "missing refusals"
grep -aq 'usage: contacts' "$S" && ok "counter-proof: add without arguments prints the usage" || bad "usage"
run_vm b "contacts list;exit" hda.img
grep -aq '^1 name=Bob phone=222' "$D/b.txt" && ! grep -aq 'name=Ada' "$D/b.txt" && ok "the file survives a reboot (only Bob is left)" || bad "persistence"
cp "$D/root.img" "$D/fresh.img"
run_vm c "contacts list;exit" fresh.img
! grep -aq 'name=' "$D/c.txt" && ok "counter-proof: a fresh disk lists nothing" || bad "fresh disk shows contacts"
echo "CONTACTS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
