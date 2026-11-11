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
finish() { echo "NVMETIMEOUT: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
BIG_BYTES=${BIG_BYTES:-1048576}

echo "== 1. build =="
PROGS="sh cat shasum echo"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; finish; }
./tools/build-kernel.sh "$D/k.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; finish; }
head -c "$BIG_BYTES" /dev/urandom > "$D/big.bin"
WANT=$(sha256sum "$D/big.bin" | cut -d' ' -f1)
printf 'shasum /t/big\ncat /t/big > /tmp/copy\nshasum /tmp/copy\necho ==END==\n' > "$D/s.sh"
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
        -drive "file=$D/d-$name.img,format=raw,if=none,id=d0" -device nvme,drive=d0,serial=tmo \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}

count() { grep -ac "$1" "$D/$2.klar"; }

echo "== 2. runs =="
run clean ""
run lost "nvmelost"

echo "== 3. checks =="
for n in clean lost; do
    grep -aq "rootsel: nvme" "$D/$n.klar" && ok "$n: root on nvme" || bad "$n: root not on nvme"
    [ "$(count "^$WANT  /t/big" $n)" -ge 1 ] && ok "$n: /t/big hash matches" || bad "$n: /t/big hash differs"
    [ "$(count "^$WANT  /tmp/copy" $n)" -ge 1 ] && ok "$n: written copy reads back identical" || bad "$n: copy hash differs"
    grep -aq "==END==" "$D/$n.klar" && ok "$n: script finished" || bad "$n: script did not finish"
    grep -aq "nvme: noirq" "$D/$n.klar" && bad "$n: nvme mode flags leaked into the log" || ok "$n: no spurious noirq"
done
[ "$(count "nvme: command timeout" clean)" -eq 0 ] && ok "clean: no command timeout" || bad "clean: unexpected command timeout"
[ "$(count "nvme: controller reset" clean)" -eq 0 ] && ok "clean: no controller reset" || bad "clean: unexpected controller reset"
[ "$(count "nvme: command timeout" lost)" -eq 1 ] && ok "lost: exactly one command timeout" || bad "lost: timeout count $(count "nvme: command timeout" lost)"
[ "$(count "nvme: controller reset" lost)" -eq 1 ] && ok "lost: controller reset after the timeout" || bad "lost: reset count $(count "nvme: controller reset" lost)"
grep -aq "nvme: reset failed\|nvme: reinit failed" "$D/lost.klar" && bad "lost: reset path reported a failure" || ok "lost: reset and reinit succeeded"
finish
