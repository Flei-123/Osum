#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
. tools/lib/firnenv.sh
finish() { echo "AHCIIRQ: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
BIG_BYTES=${BIG_BYTES:-1048576}
MIN_IRQS=${MIN_IRQS:-8}

echo "== 1. build =="
PROGS="sh cat shasum echo"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
./tools/build-kernel.sh "$D/k.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
head -c "$BIG_BYTES" /dev/urandom > "$D/big.bin"
WANT=$(sha256sum "$D/big.bin" | cut -d' ' -f1)
printf 'shasum /t/big\ncat /t/big > /tmp/copy\nshasum /tmp/copy\ncat /proc/bench\necho ==END==\n' > "$D/s.sh"
SPEC="/bin/ /t/ /tmp/ /proc/ /dev/ /var/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$D/bin/$p.elf"; done
bash tools/mkfsfi/mkfs.sh build "$D/d.img" 16384 $SPEC "/t/s.sh=$D/s.sh" "/t/big=$D/big.bin" > "$D/mkfs.txt" 2>&1 \
    && ok "image built" || { bad "mkfs"; tail -3 "$D/mkfs.txt"; finish; }

run() {
    local name=$1 words=$2
    cp "$D/d.img" "$D/d-$name.img"
    timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k.img" -m 512 \
        -append "osum nokbd vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -device ahci,id=ahci -drive "file=$D/d-$name.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ahci.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}

count() { grep -ac "$1" "$D/$2.klar"; }
stat() { grep -a "^blk\.$2 " "$D/$1.klar" | tail -1 | cut -d' ' -f2; }

echo "== 2. runs =="
run clean "ahciirqall"
run demand ""
run noirq "noahciirq"

echo "== 3. checks =="
for n in clean demand noirq; do
    grep -aq "rootsel: ahci" "$D/$n.klar" && ok "$n: root on ahci" || bad "$n: root not on ahci"
    [ "$(count "^$WANT  /t/big" $n)" -ge 1 ] && ok "$n: /t/big hash matches" || bad "$n: /t/big hash differs"
    [ "$(count "^$WANT  /tmp/copy" $n)" -ge 1 ] && ok "$n: written copy reads back identical" || bad "$n: copy hash differs"
    grep -aq "==END==" "$D/$n.klar" && ok "$n: script finished" || bad "$n: script did not finish"
done
IRQS=$(stat clean ahci_irqs); SLEEPS=$(stat clean ahci_sleeps); CMDS=$(stat clean ahci_cmds)
echo "  clean: cmds=${CMDS:-?} irqs=${IRQS:-?} sleeps=${SLEEPS:-?}"
[ "$(count "ahci: interrupts on" clean)" -eq 1 ] && ok "clean: interrupts armed once" || bad "clean: arm count $(count "ahci: interrupts on" clean)"
[ "${IRQS:-0}" -ge "$MIN_IRQS" ] && ok "clean: completion interrupts arrive ($IRQS)" || bad "clean: only ${IRQS:-0} interrupts"
[ "$(count "interrupt lost" clean)" -eq 0 ] && ok "clean: no fallback to polling" || bad "clean: fell back to polling"
DIRQS=$(stat demand ahci_irqs)
echo "  demand: irqs=${DIRQS:-?}"
[ "${DIRQS:-99}" -le 2 ] && ok "demand: completion interrupts stay off while polling ($DIRQS)" || bad "demand: $DIRQS interrupts while polling"
NIRQS=$(stat noirq ahci_irqs); NSLEEPS=$(stat noirq ahci_sleeps)
echo "  noirq: irqs=${NIRQS:-?} sleeps=${NSLEEPS:-?}"
[ "$(count "ahci: interrupts on" noirq)" -eq 0 ] && ok "noirq: interrupts stay off" || bad "noirq: interrupts armed"
[ "${NIRQS:-1}" -eq 0 ] && [ "${NSLEEPS:-1}" -eq 0 ] && ok "noirq: pure polling, no sleeps" || bad "noirq: irqs=$NIRQS sleeps=$NSLEEPS"
finish
