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
bash tools/module/build.sh "$D/fwdemo.omod" --quelle module/store/fwdemo.fi > "$D/mf.txt" 2>&1 && ok "fwdemo module builds and is signed" || { bad "fwdemo module"; tail -5 "$D/mf.txt"; }
PROGS="sh cat echo drvctl"
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
        -append "osum vfs $words script=sh ${SCRIPT:-/t/s.sh};exit" \
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
mkdir -p "$D/pksrc"
python3 tools/drvstore/mkpkg.py build "$D/pksrc" --module "$MK" --name newdrv --rank 5 --match "pci 8086:24fd:8086:9010" --match "pciclass 0280" > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pksrc" --module "$MK" --name generic --rank 99 --match "pci 8086:24fd" > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pksrc" --module "$MK" --name evil --rank 99 --match "pci 8086:24fd" --bad-sig > /dev/null
SRCF="/t/src/"
for p in newdrv generic evil; do
    SRCF="$SRCF /t/src/$p/"
    for f in $(ls "$D/pksrc/$p"); do SRCF="$SRCF /t/src/$p/$f=$D/pksrc/$p/$f"; done
done
cat > "$D/c1.sh" <<'EOS'
echo ==C1==
drvctl list
drvctl match pci 1234:11e8
drvctl match pci 8086:ffff
drvctl match pci 9999:9999
drvctl install /t/src/newdrv
drvctl install /t/src/generic
drvctl install /t/src/evil
drvctl install /t/src/nothing
drvctl match pci 8086:24fd:8086:9010
drvctl match pci 8086:24fd:1111:2222
drvctl match pciclass 0280:00
drvctl ban edudemo
drvctl ban BAD/NAME
drvctl match pci 1234:11e8
cat /etc/drivers.deny
drvctl remove generic
drvctl remove nosuch
drvctl match pci 8086:24fd:1111:2222
drvctl list
drvctl
echo ==C1END==
EOS
cat > "$D/c2.sh" <<'EOS'
echo ==C2==
cat /proc/drivers
echo ==C2END==
EOS
mkimg ctl1 $FILES $SRCF "/t/c1.sh=$D/c1.sh" "/t/c2.sh=$D/c2.sh" /etc/
SCRIPT=/t/c1.sh runvm ctl1 "" -device edu
cp "$D/d-ctl1.img" "$D/d-ctl2.img"
SCRIPT=/t/c2.sh runvm ctl2 "" -device edu
has "$D/ctl1.klar" "pkg edudemo version=1 rank=10 sig=ok" "ctl list: good package listed"
has "$D/ctl1.klar" "pkg badsig sig=bad" "ctl list: bad signature shown"
has "$D/ctl1.klar" "pkg tampered sig=bad" "ctl list: tampered shown as bad"
has "$D/ctl1.klar" "pkg wrongabi version=1 rank=95 sig=ok invalid" "ctl list: wrong ABI marked invalid"
has "$D/ctl1.klar" "pkg nomod version=1 rank=96 sig=ok invalid" "ctl list: missing module marked invalid"
has "$D/ctl1.klar" "pkg garbage version=1 rank=97 sig=ok invalid" "ctl list: bad manifest line marked invalid"
has "$D/ctl1.klar" "packages=8 valid=3" "ctl list: counts match the kernel (3 usable of 8)"
has "$D/ctl1.klar" "match edudemo spec=30 rank=10 version=1" "ctl match: rank wins among equal specificity"
has "$D/ctl1.klar" "match unrelated spec=30" "ctl match: exact id"
has "$D/ctl1.klar" "match none" "ctl match: no package for unknown id"
has "$D/ctl1.klar" "installed newdrv (active after reboot)" "ctl install: signed package installed"
has "$D/ctl1.klar" "installed generic (active after reboot)" "ctl install: second package installed"
has "$D/ctl1.klar" "drvctl: signature check failed for /t/src/evil" "ctl install: bad signature refused"
hasnot "$D/ctl1.klar" "installed evil" "counter-proof ctl install: evil not installed"
has "$D/ctl1.klar" "drvctl: install needs a dir" "ctl install: missing dir refused"
has "$D/ctl1.klar" "match newdrv spec=40" "ctl match: subsystem beats a higher rank"
has "$D/ctl1.klar" "match generic spec=30 rank=99" "ctl match: other subsystem falls back"
has "$D/ctl1.klar" "match newdrv spec=15 rank=5" "ctl match: pciclass"
has "$D/ctl1.klar" "banned edudemo (active after reboot)" "ctl ban: written"
has "$D/ctl1.klar" "drvctl: bad package name: BAD/NAME" "ctl ban: path-like name refused"
has "$D/ctl1.klar" "match lowrank spec=30 rank=1" "ctl match: banned package skipped"
has "$D/ctl1.klar" "removed generic" "ctl remove: done"
has "$D/ctl1.klar" "drvctl: no such package" "ctl remove: unknown name refused"
has "$D/ctl1.klar" "usage: drvctl" "ctl: usage text"
has "$D/ctl2.klar" "drvstore: pkg edudemo ok banned" "ctl reboot: ban survives, package banned"
has "$D/ctl2.klar" "drv=lowrank src=store bind=bound" "ctl reboot: next package binds after ban"
has "$D/ctl2.klar" "drvstore: pkg newdrv ok" "ctl reboot: installed package scanned and valid"
hasnot "$D/ctl2.klar" "drvstore: pkg generic" "ctl reboot: removed package gone"
hasnot "$D/ctl2.klar" "drvstore: pkg evil" "counter-proof ctl reboot: refused package absent"

cat > "$D/u1.sh" <<'EOS'
echo ==U1==
cat /proc/drivers
drvctl unload edudemo
cat /proc/drivers
drvctl unload edudemo
drvctl unload lowrank
drvctl unload nosuch
drvctl unload BAD/NAME
drvctl unload
echo ==U1END==
EOS
mkimg ul1 $FILES "/t/u1.sh=$D/u1.sh"
cp "$D/d-ul1.img" "$D/d-ul2.img"
cp "$D/d-ul1.img" "$D/d-ul3.img"
SCRIPT=/t/u1.sh runvm ul1 "" -device edu &
SCRIPT=/t/u1.sh runvm ul2 drvhold -device edu &
SCRIPT=/t/u1.sh runvm ul3 nostore -device edu &
wait
awk '/==U1==/{f=1} f&&/unload edudemo ok/{exit} f' "$D/ul1.klar" > "$D/ul1.before"
awk '/unload edudemo ok/{f=1} f' "$D/ul1.klar" > "$D/ul1.after"
has "$D/ul1.before" "drv=edudemo src=store bind=bound" "unload: driver bound before"
has "$D/ul1.before" "store=on pkgs=8 valid=3 bound=1 failed=0" "unload: store counts before"
[ -n "${DRVSTORE_DUMP:-}" ] && mkdir -p "$DRVSTORE_DUMP" && cp "$D"/ul*.klar "$DRVSTORE_DUMP"/
has "$D/ul1.klar" "unload edudemo ok" "unload: package unloaded"
has "$D/ul1.klar" "drvstore: ctl unload edudemo 0" "unload: kernel logged the request"
hasnot "$D/ul1.after" "drv=edudemo src=store" "unload: device no longer shown as bound to the package"
has "$D/ul1.after" "store=on pkgs=8 valid=3 bound=0 failed=0" "unload: bound count dropped to 0"
has "$D/ul1.after" "unload edudemo idle" "unload: second unload says idle (nothing loaded)"
has "$D/ul1.after" "unload lowrank idle" "unload: valid but never loaded package says idle"
has "$D/ul1.after" "unload nosuch none" "unload: unknown package says none"
has "$D/ul1.after" "drvctl: bad package name: BAD/NAME" "unload: path-like name refused in userland"
has "$D/ul1.after" "usage: drvctl" "unload: missing name prints usage"
hasnot "$D/ul1.klar" "EXCEPTION" "unload: no kernel exception"
has "$D/ul2.klar" "unload edudemo busy refs=2" "hold: extra reference makes unload refuse"
has "$D/ul2.klar" "drvstore: ctl unload edudemo 3" "hold: kernel logged the refusal"
hasnot "$D/ul2.klar" "unload edudemo ok" "counter-proof hold: package not unloaded"
has "$D/ul2.klar" "store=on pkgs=8 valid=3 bound=1 failed=0" "hold: still bound after refusal"
hasnot "$D/ul2.klar" "EXCEPTION" "hold: no kernel exception"
has "$D/ul3.klar" "unload edudemo none" "nostore: nothing to unload"
hasnot "$D/ul3.klar" "unload edudemo ok" "counter-proof nostore: no unload without store"

cat > "$D/r1.sh" <<'EOS'
echo ==R1==
drvctl load edudemo
drvctl reload edudemo
cat /proc/drivers
drvctl unload edudemo
drvctl load edudemo
drvctl load edudemo
drvctl load nosuch
drvctl reload nosuch
drvctl load BAD/NAME
drvctl load
echo ==R1END==
EOS
mkimg rl1 $FILES "/t/r1.sh=$D/r1.sh"
cp "$D/d-rl1.img" "$D/d-rl2.img"
cp "$D/d-rl1.img" "$D/d-rl3.img"
SCRIPT=/t/r1.sh runvm rl1 "" -device edu &
SCRIPT=/t/r1.sh runvm rl2 drvhold -device edu &
SCRIPT=/t/r1.sh runvm rl3 nostore -device edu &
wait
has "$D/rl1.klar" "load edudemo loaded" "reload: load of an already bound package says loaded"
has "$D/rl1.klar" "unload edudemo ok" "reload: reload unloads first"
has "$D/rl1.klar" "load edudemo ok bound=1" "reload: package bound again"
has "$D/rl1.klar" "drvstore: ctl load edudemo 0" "reload: kernel logged the load"
has "$D/rl1.klar" "load nosuch none" "reload: unknown package says none"
has "$D/rl1.klar" "drvctl: bad package name: BAD/NAME" "reload: path-like name refused in userland"
has "$D/rl1.klar" "usage: drvctl" "reload: missing name prints usage"
[ "$(grep -ac 'edudemo: ven=' "$D/rl1.klar")" -ge 3 ] && ok "reload: module init ran again after each load" || bad "reload: module init count $(grep -ac 'edudemo: ven=' "$D/rl1.klar")"
[ "$(grep -ac 'drv=edudemo src=store bind=bound' "$D/rl1.klar")" -ge 1 ] && ok "reload: device bound after reload" || bad "reload: device not bound after reload"
has "$D/rl1.klar" "store=on pkgs=8 valid=3 bound=1 failed=0" "reload: counts back to one bound"
hasnot "$D/rl1.klar" "EXCEPTION" "reload: no kernel exception"
has "$D/rl2.klar" "unload edudemo busy refs=2" "hold: reload refuses while references are held"
hasnot "$D/rl2.klar" "load edudemo ok" "counter-proof hold: no load after a refused unload"
has "$D/rl3.klar" "load edudemo none" "nostore: nothing to load"
hasnot "$D/rl3.klar" "load edudemo ok" "counter-proof nostore: no load without store"

FWBLOB="OrientOS fw demo blob"
FWHASH=c44a0725b6b3e2bad7103b68b309c068f5d4a0727f515c3f257c5c0f40f8eeee
printf '%s\n' "$FWBLOB" > "$D/fw.good"
printf 'tampered fw demo blob\n' > "$D/fw.bad"
fwpk() {
    local v=$1; shift
    mkdir -p "$D/pkfw-$v"
    python3 tools/drvstore/mkpkg.py build "$D/pkfw-$v" --module "$D/fwdemo.omod" --name fwdemo --match "pci 1234:11e8" "$@" > /dev/null
}
fwimg() {
    local v=$1; local blob=$2
    local files="/lib/drivers/fwdemo/"
    for f in $(ls "$D/pkfw-$v/fwdemo"); do files="$files /lib/drivers/fwdemo/$f=$D/pkfw-$v/fwdemo/$f"; done
    local fwf="/lib/firmware/"
    [ -n "$blob" ] && fwf="/lib/firmware/ /lib/firmware/fwdemo.bin=$blob"
    mkimg "fw-$v" $files $fwf
}
fwpk good --rights mmio,fw --fw "fwdemo.bin:$FWHASH"
fwpk noright --rights mmio --fw "fwdemo.bin:$FWHASH"
fwpk nofw --rights mmio,fw
fwpk wronghash --rights mmio,fw --fw "fwdemo.bin:$(printf '0%.0s' $(seq 64))"
fwimg good "$D/fw.good"
fwpk tamper --rights mmio,fw --fw "fwdemo.bin:$FWHASH"
fwimg tamper "$D/fw.bad"
fwimg noright "$D/fw.good"
fwimg nofw "$D/fw.good"
fwimg wronghash "$D/fw.good"
fwpk missing --rights mmio,fw --fw "fwdemo.bin:$FWHASH"
fwimg missing ""
for v in good tamper noright nofw wronghash missing; do
    runvm "fw-$v" "" -device edu
done
has "$D/fw-good.klar" "drvstore: fw ok fwdemo.bin 22" "fw good: firmware verified and delivered"
has "$D/fw-good.klar" "fwdemo: fw len=22 b0=79" "fw good: module received the bytes"
hasnot "$D/fw-good.klar" "fw error" "fw good: no error"
has "$D/fw-tamper.klar" "drvstore: fw fwdemo error 9" "fw tampered file: digest mismatch refused"
has "$D/fw-tamper.klar" "fwdemo: fw none" "fw tampered file: module got nothing"
hasnot "$D/fw-tamper.klar" "fw len=" "counter-proof tampered: no bytes delivered"
has "$D/fw-noright.klar" "drvstore: fw fwdemo error 2" "fw without right fw: refused"
hasnot "$D/fw-noright.klar" "fw len=" "counter-proof noright: no bytes delivered"
has "$D/fw-nofw.klar" "drvstore: fw fwdemo error 3" "fw without manifest entry: refused"
has "$D/fw-wronghash.klar" "drvstore: fw fwdemo error 5" "fw hash differs from module expectation: refused"
has "$D/fw-missing.klar" "drvstore: fw fwdemo error 6" "fw file missing: reported"
hasnot "$D/fw-good.klar" "EXCEPTION" "fw: no kernel exception"

bash tools/module/build.sh "$D/auxdemo.omod" --quelle module/store/auxdemo.fi > "$D/ma.txt" 2>&1 && ok "auxdemo module builds and is signed" || { bad "auxdemo module"; tail -3 "$D/ma.txt"; }
bash tools/module/build.sh "$D/auxrogue.omod" --quelle module/store/auxrogue.fi > "$D/mr.txt" 2>&1 && ok "auxrogue module builds and is signed" || { bad "auxrogue module"; tail -3 "$D/mr.txt"; }
addpk() {
    local root=$1 src=$2 n=$3
    PKOUT="$PKOUT $root/$n/"
    for f in $(ls "$src/$n"); do PKOUT="$PKOUT $root/$n/$f=$src/$n/$f"; done
}
mkdir -p "$D/pkaux" "$D/pkrogue" "$D/pkapp"
python3 tools/drvstore/mkpkg.py build "$D/pkaux" --module "$D/auxdemo.omod" --name auxdemo --slot aux --match "pci 1234:11e8" > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pkaux" --module "$D/auxdemo.omod" --name auxsecond --slot aux --match "pci 1b36:0005" > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pkrogue" --module "$D/auxrogue.omod" --name rogue --slot aux --match "pci 1234:11e8" > /dev/null
cat > "$D/sl1.sh" <<'EOS'
echo ==SL1==
drvctl slots
drvctl aux 1 21
drvctl aux 2 5
drvctl aux 9 9
drvctl aux x 1
cat /proc/drivers
drvctl unload auxdemo
drvctl slots
drvctl aux 1 21
drvctl unload auxsecond
echo ==SL1END==
EOS
PKOUT=""
addpk /lib/drivers "$D/pkaux" auxdemo
addpk /lib/drivers "$D/pkaux" auxsecond
mkimg sl1 $PKOUT "/t/sl1.sh=$D/sl1.sh"
cp "$D/d-sl1.img" "$D/d-sl2.img"
PKOUT=""
addpk /lib/drivers "$D/pkrogue" rogue
mkimg rg $PKOUT "/t/sl1.sh=$D/sl1.sh"
SCRIPT=/t/sl1.sh runvm sl1 "" -device edu -device pci-testdev &
SCRIPT=/t/sl1.sh runvm sl2 nostore -device edu -device pci-testdev &
SCRIPT=/t/sl1.sh runvm rg "" -device edu &
wait
has "$D/sl1.klar" "auxdemo: ready" "slot aux: module loaded and registered"
has "$D/sl1.klar" "slots mouse=none aux=auxdemo" "slot aux: drvctl slots shows the owner"
has "$D/sl1.klar" "aux 1 21 = 42" "slot aux: control call reaches the module (cmd 1)"
has "$D/sl1.klar" "aux 2 5 = 12" "slot aux: control call reaches the module (cmd 2)"
has "$D/sl1.klar" "aux 9 9 = 0" "slot aux: unknown command answered by the module"
has "$D/sl1.klar" "drvstore: ctl aux 1 42" "slot aux: kernel logged the call"
has "$D/sl1.klar" "drvctl: bad number: x" "slot aux: non-numeric argument refused in userland"
has "$D/sl1.klar" "drv=auxdemo src=store bind=bound" "slot aux: /proc/drivers shows the bound driver"
has "$D/sl1.klar" "drv=auxsecond src=store bind=failed" "slot aux: second package for the same slot not bound"
has "$D/sl1.klar" "bind auxsecond -> " "slot aux: bind attempt logged for the second package"
has "$D/sl1.klar" "slot busy" "slot aux: refusal reason is slot busy"
has "$D/sl1.klar" "unload auxdemo ok" "slot aux: unload works"
has "$D/sl1.klar" "unload auxsecond idle" "slot aux: refused package never loaded"
awk '/unload auxdemo ok/{f=1} f' "$D/sl1.klar" > "$D/sl1.after"
has "$D/sl1.after" "slots mouse=none aux=none" "slot aux: slot free after unload"
has "$D/sl1.after" "aux none" "slot aux: control call without a module answers none"
hasnot "$D/sl1.after" "aux 1 21 = 42" "counter-proof slot aux: no answer after unload"
hasnot "$D/sl1.klar" "EXCEPTION" "slot aux: no kernel exception"
has "$D/sl2.klar" "slots mouse=none aux=none" "nostore: slots empty"
hasnot "$D/sl2.klar" "auxdemo: ready" "counter-proof nostore: aux module not loaded"
has "$D/rg.klar" "auxrogue: foreign bind rc=4" "slot rule: bind into a foreign slot refused by the kernel"
has "$D/rg.klar" "drv=rogue src=store bind=failed" "slot rule: module that grabs a foreign slot is not bound"
has "$D/rg.klar" "slots mouse=none aux=none" "slot rule: mouse slot stays empty"
hasnot "$D/rg.klar" "drv=rogue src=store bind=bound" "counter-proof slot rule: rogue never bound"
hasnot "$D/rg.klar" "EXCEPTION" "slot rule: no kernel exception"

python3 tools/drvstore/mkpkg.py build "$D/pkapp" --module "$MK" --name appdrv --rank 10 --match "pci 1234:11e8" --rights mmio > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pkapp" --module "$MK" --name appevil --rank 99 --match "pci 1234:11e8" --bad-sig > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pkapp" --module "$MK" --name ignored --rank 99 --match "pci 1234:11e8" --rights mmio > /dev/null
python3 tools/drvstore/mkpkg.py build "$D/pkapp" --module "$MK" --name dupdrv --rank 5 --match "pci 1234:11e8" --rights mmio > /dev/null
cat > "$D/ap1.sh" <<'EOS'
echo ==AP1==
drvctl list
drvctl match pci 1234:11e8
cat /proc/drivers
drvctl remove appdrv
drvctl unload appdrv
cat /proc/drivers
echo ==AP1END==
EOS
PKOUT=""
addpk /apps/hello.osp/lib "$D/pkapp" appdrv
addpk /apps/hello.osp/lib "$D/pkapp" appevil
addpk /apps/hello.osp/lib "$D/pkapp" dupdrv
addpk /apps/plain.prog/lib "$D/pkapp" ignored
addpk /lib/drivers "$D/pkapp" dupdrv
mkimg ap /apps/ /apps/hello.osp/ /apps/hello.osp/lib/ /apps/plain.prog/ /apps/plain.prog/lib/ $PKOUT "/t/ap1.sh=$D/ap1.sh"
cp "$D/d-ap.img" "$D/d-apn.img"
cp "$D/d-ap.img" "$D/d-apd.img"
echo appdrv > "$D/deny2"
PKOUT=""
addpk /apps/hello.osp/lib "$D/pkapp" appdrv
addpk /apps/hello.osp/lib "$D/pkapp" appevil
addpk /apps/hello.osp/lib "$D/pkapp" dupdrv
addpk /lib/drivers "$D/pkapp" dupdrv
mkimg apd /apps/ /apps/hello.osp/ /apps/hello.osp/lib/ $PKOUT "/etc/drivers.deny=$D/deny2" "/t/ap1.sh=$D/ap1.sh"
SCRIPT=/t/ap1.sh runvm ap "" -device edu &
SCRIPT=/t/ap1.sh runvm apn nostore -device edu &
SCRIPT=/t/ap1.sh runvm apd "" -device edu &
wait
has "$D/ap.klar" "drvstore: pkgs=4 valid=2" "apps: four packages scanned (one lib, three in the app)"
has "$D/ap.klar" "drvstore: pkg appdrv ok app=hello.osp" "apps: good package from /apps/hello.osp/lib accepted"
has "$D/ap.klar" "drvstore: pkg appevil rejected 20 app=hello.osp" "apps: bad signature in an app package rejected"
has "$D/ap.klar" "drvstore: pkg dupdrv rejected 25 app=hello.osp" "apps: same name as a /lib/drivers package rejected"
has "$D/ap.klar" "drvstore: pkg dupdrv ok" "apps: /lib/drivers package keeps the name"
hasnot "$D/ap.klar" "pkg ignored" "apps: directories not ending in .osp are not scanned"
has "$D/ap.klar" "drvstore: bind appdrv -> " "apps: app package binds (higher rank than the lib one)"
has "$D/ap.klar" "edudemo: ven=4660 dev=4584" "apps: module from the app directory ran with the device context"
has "$D/ap.klar" "drv=appdrv src=store bind=bound" "apps: /proc/drivers shows the app driver"
has "$D/ap.klar" "pkg appdrv version=1 rank=10 sig=ok" "apps: drvctl list shows the app package"
has "$D/ap.klar" "pkg appevil sig=bad" "apps: drvctl list shows the bad app package"
has "$D/ap.klar" "packages=3 valid=2" "apps: drvctl list counts both roots"
has "$D/ap.klar" "match appdrv spec=30 rank=10" "apps: drvctl match sees the app package"
has "$D/ap.klar" "drvctl: no such package" "apps: drvctl remove does not touch app packages"
has "$D/ap.klar" "unload appdrv ok" "apps: unload by name works for app packages"
hasnot "$D/ap.klar" "EXCEPTION" "apps: no kernel exception"
has "$D/apn.klar" "store=off" "nostore apps: store off"
hasnot "$D/apn.klar" "drvstore: pkg" "counter-proof nostore apps: nothing scanned"
hasnot "$D/apn.klar" "src=store" "counter-proof nostore apps: nothing bound"
has "$D/apd.klar" "drvstore: pkg appdrv ok banned app=hello.osp" "apps: deny list applies to app packages"
has "$D/apd.klar" "drv=dupdrv src=store bind=bound" "apps: next package takes over after the ban"
echo "DRVSTORE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
