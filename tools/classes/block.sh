#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
num() {
    local name=$1 value=$2 op=$3 want=$4
    if [ -z "${value:-}" ]; then bad "$name: no number (want $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"; else bad "$name: $value, want $op $want"; fi
}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
finish() { echo "CLASSES-BLOCK: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
calls() { grep -aoE '^# class-calls block=[0-9]+' "$1" | tail -1 | cut -d= -f2; }

echo "== 1. build =="
PROGS="sh cat echo"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
printf 'echo ==DRIVERS==\ncat /proc/drivers\necho ==END==\n' > "$D/s.sh"
python3 tools/osum/mkfs.py build "$D/d.img" 8192 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
for fn in init_on present_on blocks_on bsize_on flush_on; do
    num "blkdev.$fn calls the table through a pointer (indirect call)" \
        "$(objdump -d --no-show-raw-insn --disassemble=_F0.blkdev__$fn "$D/k0.img.elf" 2>/dev/null | grep -c 'call.*\*')" ge 1
done
for chip in nvme ahci; do
    num "blkdev.fi has no direct $chip operation call left" \
        "$(grep -cE "return $chip\.[a-z_]+\(" kernel/block/blkdev.fi)" eq 0
done
for cls in nvme ahci usbmsc ata; do
    num "blkreg registers the ${cls}_class table" "$(grep -c "${cls}_class.ops()" kernel/block/blkreg.fi)" eq 1
done

runvm() {
    local name=$1 words=$2; shift 2
    cp "$D/d.img" "$D/d-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum nokbd vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=none,id=d0" "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
runide() {
    local name=$1 words=$2; shift 2
    cp "$D/d.img" "$D/d-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum nokbd vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}

echo "== 2. roots through the table =="
runvm nvme "" -device nvme,drive=d0,serial=cls
runvm ahci "" -device ahci,id=a0 -device ide-hd,drive=d0,bus=a0.0
runide ide ""
runvm nvmeno "noclass" -device nvme,drive=d0,serial=cls
runvm ahcino "noclass" -device ahci,id=a0 -device ide-hd,drive=d0,bus=a0.0
runvm nvmebad "badclass" -device nvme,drive=d0,serial=cls
[ -n "${CLASSES_DUMP:-}" ] && cp "$D"/*.klar "$CLASSES_DUMP"/
finish
