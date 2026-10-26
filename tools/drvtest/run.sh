#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=${DRVTEST_DIR:-$(mktemp -d)}; [ -z "${DRVTEST_DIR:-}" ] && trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/module/build.sh "$D/edudemo.omod" --quelle module/store/edudemo.fi > "$D/m.txt" 2>&1 && ok "module builds" || { bad "module"; tail -5 "$D/m.txt"; echo "DRVTEST: $pass passed, $fail failed"; exit 1; }
python3 - "$D/edudemo.omod" "$D/unsigned.omod" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
for i in range(len(d) - 64, len(d)):
    d[i] ^= 0x5A
open(sys.argv[2], "wb").write(d)
PY
mkdir -p "$D/bin" "$D/pk"
PROGS="sh cat echo drvctl"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; echo "DRVTEST: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; echo "DRVTEST: $pass passed, $fail failed"; exit 1; }
python3 tools/drvstore/mkpkg.py build "$D/pk" --name unsignedpkg --match "pci 1234:11e8" --rank 99 --bad-sig --module "$D/unsigned.omod" --rights mmio > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pk" --name signedpkg --match "pci 8086:ffff" --module "$D/edudemo.omod" > /dev/null
cat > "$D/s.sh" <<'EOS'
echo ==DRIVERS==
cat /proc/drivers
echo ==END==
EOS
echo "testmode=1" > "$D/conf"
echo "testmode=0" > "$D/conf0"
FILES=""
for p in $(ls "$D/pk"); do
    FILES="$FILES /lib/drivers/$p/"
    for f in $(ls "$D/pk/$p"); do FILES="$FILES /lib/drivers/$p/$f=$D/pk/$p/$f"; done
done
mkimg() {
    local name=$1; shift
    python3 tools/osum/mkfs.py build "$D/d-$name.img" 20000 /lib/ /lib/drivers/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 -device edu >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
mkimg off $FILES
mkimg off0 $FILES "/etc/drvstore.conf=$D/conf0"
mkimg on $FILES "/etc/drvstore.conf=$D/conf"
runvm off &
runvm off0 &
runvm on &
wait
for n in off off0; do
    has "$D/$n.klar" "drvstore: pkg unsignedpkg rejected 20" "$n: unsigned package rejected without test mode"
    hasnot "$D/$n.klar" "unsigned accepted" "$n: no unsigned module loaded"
    hasnot "$D/$n.klar" "testmode=on" "$n: no test mode reported"
    has "$D/$n.klar" "drvstore: pkg signedpkg ok" "$n: signed package still accepted"
done
has "$D/on.klar" "drvstore: pkg unsignedpkg ok unsigned" "on: unsigned package accepted in test mode"
has "$D/on.klar" "drvstore: pkg signedpkg ok" "on: signed package accepted"
hasnot "$D/on.klar" "drvstore: pkg signedpkg ok unsigned" "on: signed package not marked unsigned"
has "$D/on.klar" "module: unsigned accepted (testmode)" "on: kernel loader accepted the unsigned module"
has "$D/on.klar" "drvstore: bind unsignedpkg -> " "on: device bound to the unsigned package"
has "$D/on.klar" "drvstore: testmode=on" "on: store reports test mode"
echo "DRVTEST: $pass passed, $fail failed"
[ "$fail" = 0 ]
