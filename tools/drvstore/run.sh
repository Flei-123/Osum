#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d); [ -z "${DRVSTORE_KEEP:-}" ] && trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/module/build.sh "$D/edudemo.omod" --quelle module/store/edudemo.fi > "$D/m.txt" 2>&1 && ok "edudemo module builds and is signed" || { bad "module"; tail -5 "$D/m.txt"; echo "DRVSTORE: $pass passed, $fail failed"; exit 1; }
PROGS="sh cat echo"
mkdir -p "$D/bin" "$D/pk"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; echo "DRVSTORE: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; echo "DRVSTORE: $pass passed, $fail failed"; exit 1; }
MK="$D/edudemo.omod"
mkp() { python3 tools/drvstore/mkpkg.py build "$D/pk" --module "$MK" "$@" > /dev/null; }
mkp --name edudemo --match "pci 1234:11e8" --rights mmio
mkp --name badsig --match "pci 1234:11e8" --rank 99 --bad-sig
mkp --name tampered --match "pci 1234:11e8" --rank 98 --tamper
mkp --name garbage --match "pci 1234:11e8" --rank 97 --garbage
mkp --name nomod --match "pci 1234:11e8" --rank 96 --no-module
mkp --name wrongabi --match "pci 1234:11e8" --rank 95 --abi 2
mkp --name lowrank --match "pci 1234:11e8" --rank 1 --rights mmio
mkp --name unrelated --match "pci 8086:ffff"
cat > "$D/s.sh" <<'EOS'
echo ==DRIVERS==
cat /proc/drivers
echo ==END==
EOS
echo edudemo > "$D/deny"
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
    local name=$1; local words=$2; shift 2
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
mkimg all $FILES
mkimg deny $FILES "/etc/drivers.deny=$D/deny"
mkimg empty
for n in edu nostore noedu; do cp "$D/d-all.img" "$D/d-$n.img"; done
runvm edu "" -device edu
runvm nostore nostore -device edu
runvm noedu "" 
runvm deny "" -device edu
runvm empty "" -device edu
has "$D/edu.klar" "drvstore: pkgs=8 valid=3" "edu: 8 packages scanned, 3 valid"
has "$D/edu.klar" "drvstore: pkg edudemo ok" "edu: good package accepted"
has "$D/edu.klar" "drvstore: pkg badsig rejected 20" "edu: bad signature rejected"
has "$D/edu.klar" "drvstore: pkg tampered rejected 20" "edu: tampered manifest rejected"
has "$D/edu.klar" "drvstore: pkg garbage rejected 1" "edu: signed manifest with a bad line rejected (syntax)"
has "$D/edu.klar" "drvstore: pkg nomod rejected 22" "edu: missing module rejected"
has "$D/edu.klar" "drvstore: pkg wrongabi rejected 21" "edu: wrong ABI rejected"
has "$D/edu.klar" "drvstore: bind edudemo -> " "edu: device bound to edudemo, not to lowrank"
has "$D/edu.klar" "edudemo: ven=4660 dev=4584" "edu: module ran with the device context"
has "$D/edu.klar" " id=16777453" "edu: module read the device id register through BAR0"
has "$D/edu.klar" "1234:11e8" "edu: /proc/drivers lists the device"
has "$D/edu.klar" "drv=edudemo src=store bind=bound" "edu: /proc/drivers shows store driver bound"
has "$D/edu.klar" "store=on pkgs=8 valid=3 bound=1 failed=0" "edu: store summary line"
has "$D/edu.klar" "drv=none src=none bind=-" "edu: devices without driver are listed as none"
hasnot "$D/edu.klar" "bind lowrank" "edu: lower rank package not used"
hasnot "$D/edu.klar" "EXCEPTION" "edu: no kernel exception"
has "$D/nostore.klar" "store=off" "nostore: store off"
hasnot "$D/nostore.klar" "drvstore:" "counter-proof nostore: nothing scanned"
hasnot "$D/nostore.klar" "src=store" "counter-proof nostore: no store binding"
has "$D/noedu.klar" "store=on pkgs=8 valid=3 bound=0" "noedu: no device, no bind"
hasnot "$D/noedu.klar" "edudemo: ven" "counter-proof noedu: module not loaded"
has "$D/deny.klar" "drvstore: pkg edudemo ok banned" "deny: package marked banned"
has "$D/deny.klar" "drv=lowrank src=store bind=bound" "deny: next package takes over"
has "$D/empty.klar" "store=on pkgs=0 valid=0 bound=0" "empty: no packages"
hasnot "$D/empty.klar" "src=store" "counter-proof empty: nothing bound"
echo "DRVSTORE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
