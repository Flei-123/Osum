#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT; osum_tmp_guard "${1:-}" "$D"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
fin() { echo "DRVLOOSE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

PROGS="sh cat echo drvctl"
mkdir -p "$D/bin" "$D/pk"
bash tools/module/build.sh "$D/auxdemo.omod" --quelle module/store/auxdemo.fi > "$D/m1.txt" 2>&1 && ok "auxdemo module builds and is signed" || { bad "auxdemo module"; tail -3 "$D/m1.txt"; fin; }
bash tools/module/build.sh "$D/mousedemo.omod" --quelle module/store/mousedemo.fi > "$D/m2.txt" 2>&1 && ok "mousedemo module builds and is signed" || { bad "mousedemo module"; tail -3 "$D/m2.txt"; fin; }
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; fin; }
python3 -c "
d = bytearray(open('$D/auxdemo.omod', 'rb').read())
d[-1] ^= 1
open('$D/auxbad.omod', 'wb').write(d)
print(open('$D/auxdemo.omod', 'rb').read()[-64:].hex())
" > "$D/floor.txt"
cp "$D/auxdemo.omod" "$D/foreign.omod"
python3 tools/drvstore/mkpkg.py build "$D/pk" --module "$D/auxdemo.omod" --name auxpkg --slot aux --match "pci 1234:11e8" > /dev/null

kb() { local n=$1; shift; ./tools/build-kernel.sh "$D/k-$n.img" --stufe 0 "$@" > "$D/kb-$n.txt" 2>&1; }
kb def &
P1=$!
kb nops2m --ohne-ps2m &
P2=$!
kb floor --ban-floor "$D/floor.txt" &
P3=$!
wait $P1 && ok "default kernel builds" || { bad "default kernel"; tail -3 "$D/kb-def.txt"; fin; }
wait $P2 && ok "kernel without built-in ps2m builds" || { bad "kernel without ps2m"; tail -3 "$D/kb-nops2m.txt"; fin; }
wait $P3 && ok "kernel with a compiled-in revocation floor builds" || { bad "floor kernel"; tail -3 "$D/kb-floor.txt"; fin; }

cat > "$D/s.sh" <<'EOS'
echo ==LOOSE==
drvctl slots
drvctl aux 1 21
drvctl unload auxdemo
drvctl slots
drvctl unload mousedemo
drvctl slots
drvctl unload nothing
echo ==LOOSEEND==
EOS
echo auxdemo > "$D/deny"

mkimg() {
    local name=$1; shift
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ /lib/drivers/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /apps/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1; local kern=$2; local words=$3; shift 3
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k-$kern.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}

LIB=/apps/lo.osp/lib
mkimg aux /apps/lo.osp/ $LIB/ "$LIB/auxdemo.omod=$D/auxdemo.omod"
mkimg mouse /apps/lo.osp/ $LIB/ "$LIB/mousedemo.omod=$D/mousedemo.omod"
mkimg deny /apps/lo.osp/ $LIB/ "$LIB/auxdemo.omod=$D/auxdemo.omod" "/etc/drivers.deny=$D/deny"
mkimg bad /apps/lo.osp/ $LIB/ "$LIB/auxdemo.omod=$D/auxbad.omod"
mkimg prog /apps/lo.prog/ /apps/lo.prog/lib/ "/apps/lo.prog/lib/auxdemo.omod=$D/auxdemo.omod"
mkimg foreign /apps/lo.osp/ $LIB/ "$LIB/foreign.omod=$D/foreign.omod"
mkimg busy /apps/lo.osp/ $LIB/ "$LIB/auxdemo.omod=$D/auxdemo.omod" /lib/drivers/auxpkg/ \
    "/lib/drivers/auxpkg/driver.inf=$D/pk/auxpkg/driver.inf" "/lib/drivers/auxpkg/driver.inf.sig=$D/pk/auxpkg/driver.inf.sig" \
    "/lib/drivers/auxpkg/auxdemo.omod=$D/pk/auxpkg/auxdemo.omod"
for n in nostore floor; do cp "$D/d-aux.img" "$D/d-$n.img"; done

runvm aux def "" &
runvm nostore def nostore &
runvm deny def "" &
runvm bad def "" &
runvm prog def "" &
wait
runvm foreign def "" &
runvm busy def "" -device edu &
runvm floor floor "" &
runvm mouse nops2m "" &
wait

for n in aux nostore deny bad prog foreign busy floor mouse; do
    has "$D/$n.klar" "==LOOSEEND==" "$n: boot script finished"
    hasnot "$D/$n.klar" "EXCEPTION" "$n: no kernel exception"
done
has "$D/aux.klar" "drvstore: loose auxdemo ok app=lo.osp" "aux: loose module from /apps/lo.osp/lib loaded at boot"
has "$D/aux.klar" "auxdemo: ready" "aux: module init ran"
has "$D/aux.klar" "slots mouse=none aux=auxdemo" "aux: slot owner is the loose module"
has "$D/aux.klar" "aux 1 21 = 42" "aux: control call reaches the loose module"
has "$D/aux.klar" "unload auxdemo ok" "aux: unload by name works"
awk '/unload auxdemo ok/{f=1} f' "$D/aux.klar" > "$D/aux.after"
has "$D/aux.after" "slots mouse=none aux=none" "aux: slot free after unload"
has "$D/aux.klar" "unload nothing none" "aux: unknown name answered none"
has "$D/aux.klar" "pkgs=0 valid=0" "aux: loose file is not counted as a package"
hasnot "$D/nostore.klar" "drvstore: loose" "counter-proof nostore: nothing loaded"
hasnot "$D/nostore.klar" "auxdemo: ready" "counter-proof nostore: module never ran"
has "$D/deny.klar" "drvstore: loose auxdemo banned app=lo.osp" "deny list: loose module refused"
hasnot "$D/deny.klar" "auxdemo: ready" "counter-proof deny list: module never ran"
has "$D/deny.klar" "slots mouse=none aux=none" "deny list: slot stays empty"
has "$D/bad.klar" "drvstore: loose auxdemo fail:" "bad signature: loose module rejected"
hasnot "$D/bad.klar" "auxdemo: ready" "counter-proof bad signature: module never ran"
has "$D/bad.klar" "slots mouse=none aux=none" "bad signature: slot stays empty"
hasnot "$D/prog.klar" "drvstore: loose" "counter-proof: /apps/*.prog is not scanned"
hasnot "$D/prog.klar" "auxdemo: ready" "counter-proof: module in a .prog directory never ran"
hasnot "$D/foreign.klar" "drvstore: loose" "unknown module name: skipped without a log line"
hasnot "$D/foreign.klar" "auxdemo: ready" "counter-proof unknown module name: never ran"
has "$D/busy.klar" "drvstore: bind auxpkg -> " "slot busy: package bound first"
has "$D/busy.klar" "drvstore: loose auxdemo slot busy app=lo.osp" "slot busy: loose module refused, slot already owned"
has "$D/busy.klar" "slots mouse=none aux=auxpkg" "slot busy: package keeps the slot"
has "$D/floor.klar" "drvstore: loose auxdemo fail: revoked app=lo.osp" "floor kernel: revoked loose module refused without any list file"
hasnot "$D/floor.klar" "auxdemo: ready" "counter-proof floor kernel: module never ran"
has "$D/mouse.klar" "drvstore: loose mousedemo ok app=lo.osp" "mouse: loose module loaded into the mouse slot"
has "$D/mouse.klar" "slots mouse=mousedemo aux=none" "mouse: slot owner is the loose module"
has "$D/mouse.klar" "unload mousedemo ok" "mouse: unload by name works"
fin
