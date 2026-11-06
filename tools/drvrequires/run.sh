#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
count_is() { local n; n=$(grep -acF -- "$2" "$1"); [ "$n" -eq "$4" ] && ok "$3" || bad "$3 -- '$2' count $n, want $4"; }
D=$(mktemp -d); [ -z "${REQUIRES_KEEP:-}" ] && trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
fin() { echo "DRVSTORE-REQUIRES: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
for m in provdemo provother consdemo; do
    bash tools/module/build.sh "$D/$m.omod" --quelle "module/store/$m.fi" > "$D/m-$m.txt" 2>&1 && ok "$m module builds and is signed" || { bad "$m module"; tail -5 "$D/m-$m.txt"; fin; }
done
MK="python3 -I tools/drvstore/mkpkg.py"
mkdir -p "$D/bin" "$D/pk" "$D/src"
PROGS="sh cat echo drvctl"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; fin; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }

$MK build "$D/pk" --name consdemo --module "$D/consdemo.omod" --requires "$D/provdemo.omod" --match "pci 1234:11e8" > /dev/null
$MK build "$D/pk" --name consbare --module "$D/consdemo.omod" --match "pci 1b36:0005" > /dev/null
$MK build "$D/pk" --name consother --module "$D/consdemo.omod" --requires "$D/provother.omod" --match "pci 1b36:0002" > /dev/null
$MK build "$D/pk" --name noprov --module "$D/consdemo.omod" --requires "$D/provdemo.omod" --no-requires --match "pci 8086:ffff" > /dev/null
$MK build "$D/src" --name consinst --module "$D/consdemo.omod" --requires "$D/provdemo.omod" --match "pci 8086:fffe" > /dev/null
$MK build "$D/src" --name consbroken --module "$D/consdemo.omod" --requires "$D/provdemo.omod" --no-requires --match "pci 8086:fffd" > /dev/null
[ "$($MK check "$D/pk/consdemo")" = OK ] && ok "mkpkg check: package with provider passes" || bad "mkpkg check: package with provider"
($MK check "$D/pk/noprov" || true) | grep -q "required file provdemo.omod missing" && ok "counter-proof mkpkg check: missing provider file reported" || bad "mkpkg check: missing provider accepted"
grep -q "^requires=provdemo.omod$" "$D/pk/consdemo/driver.inf" && ok "manifest carries requires=" || bad "manifest lacks requires="
$MK build "$D/x" --name selfreq --module "$D/consdemo.omod" --requires "$D/consdemo.omod" --match "pci 1234:11e8" >/dev/null 2>&1 && bad "requires equal to module accepted" || ok "counter-proof mkpkg: requires equal to module refused"
$MK build "$D/x" --name badreq --module "$D/consdemo.omod" --requires "$D/bad name.omod" --match "pci 1234:11e8" >/dev/null 2>&1 && bad "bad requires name accepted" || ok "counter-proof mkpkg: bad requires file name refused"

FILES=""
for p in $(ls "$D/pk"); do
    FILES="$FILES /lib/drivers/$p/"
    for f in $(ls "$D/pk/$p"); do FILES="$FILES /lib/drivers/$p/$f=$D/pk/$p/$f"; done
done
SRCF="/t/src/"
for p in $(ls "$D/src"); do
    SRCF="$SRCF /t/src/$p/"
    for f in $(ls "$D/src/$p"); do SRCF="$SRCF /t/src/$p/$f=$D/src/$p/$f"; done
done
cat > "$D/a.sh" <<'EOS'
echo ==A==
cat /proc/drivers
echo ==UNLOAD==
drvctl unload consdemo
echo ==RELOAD==
drvctl load consdemo
echo ==INSTALL==
drvctl install /t/src/consinst
drvctl install /t/src/consbroken
drvctl list
echo ==AEND==
EOS
cat > "$D/c.sh" <<'EOS'
echo ==C==
cat /proc/drivers
echo ==RETRY==
drvctl load consother
drvctl load consother
echo ==CEND==
EOS
cat > "$D/s.sh" <<'EOS'
echo ==S==
cat /proc/drivers
echo ==SEND==
EOS
mkimg() {
    local name=$1; shift
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ /lib/drivers/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/a.sh=$D/a.sh" "/t/c.sh=$D/c.sh" "/t/s.sh=$D/s.sh" "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
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
mkimg all $FILES $SRCF
for n in a b c; do cp "$D/d-all.img" "$D/d-$n.img"; done
SCRIPT=/t/a.sh runvm a "" -device edu
SCRIPT=/t/s.sh runvm b "" -device pci-testdev
SCRIPT=/t/c.sh runvm c "" -device pci-serial
has "$D/a.klar" "==AEND==" "A: script ran to the end"
has "$D/b.klar" "==SEND==" "B: script ran to the end"
has "$D/c.klar" "==CEND==" "C: script ran to the end"
has "$D/a.klar" "drvstore: pkg consdemo ok" "A: package with requires= accepted at scan"
has "$D/a.klar" "drvstore: pkg noprov rejected 27" "A: declared provider file missing is rejected at scan (27)"
has "$D/a.klar" "provdemo: init" "A: provider module loaded"
has "$D/a.klar" "consdemo: add=42 next=1 next=2" "A: consumer called provider functions and provider state (add=42, counter 1,2)"
has "$D/a.klar" "drvstore: bind consdemo -> " "A: consumer bound to the device"
awk '/==A==/{f=1} f' "$D/a.klar" > "$D/a.run"
awk '/provdemo: init/{if(!i)i=NR} /consdemo: add=/{if(!c)c=NR} END{exit !(i>0 && c>i)}' "$D/a.klar" && ok "A: provider init runs before the consumer" || bad "A: provider init not before consumer"
has "$D/a.klar" "drv=consdemo src=store bind=bound" "A: /proc/drivers shows the consumer bound"
awk '/==UNLOAD==/{f=1} /==RELOAD==/{f=0} f' "$D/a.run" > "$D/a.unload"
has "$D/a.unload" "unload consdemo ok" "A: consumer unloads (provider reference released)"
has "$D/a.unload" "consdemo: exit" "A: consumer exit ran on unload"
has "$D/a.unload" "provdemo: exit" "A: provider unloaded after its last user"
awk '/consdemo: exit/{c=NR} /provdemo: exit/{p=NR} END{exit !(c>0 && p>c)}' "$D/a.unload" && ok "A: consumer exits before provider (unload order)" || bad "A: unload order wrong"
awk '/==RELOAD==/{f=1} /==INSTALL==/{f=0} f' "$D/a.run" > "$D/a.reload"
has "$D/a.reload" "load consdemo ok bound=1" "A: reload binds again"
has "$D/a.reload" "provdemo: init" "A: provider loaded again for the reload"
has "$D/a.reload" "consdemo: add=42 next=1 next=2" "A: provider state restarted (fresh provider instance, no leak)"
count_is "$D/a.klar" "provdemo: init" "A: provider initialised exactly twice (boot + reload)" 2
awk '/==INSTALL==/{f=1} f' "$D/a.run" > "$D/a.inst"
has "$D/a.inst" "installed consinst" "A: drvctl install accepts a package with a provider"
has "$D/a.inst" "pkg consinst version=1 rank=10 sig=ok tier=native" "A: installed package is usable (provider copied, not marked invalid)"
has "$D/a.inst" "drvctl: cannot copy provdemo.omod" "A: counter-proof install: missing provider file refused"
hasnot "$D/a.klar" "EXCEPTION" "A: no kernel exception"
has "$D/b.klar" "drvstore: bind consbare -> " "B: bare consumer bound to the testdev"
has "$D/b.klar" "fail: symbol" "B: without requires= the provider is not loaded: unresolved symbol (R_SYM)"
hasnot "$D/b.klar" "provdemo: init" "B: counter-proof: provider never loaded"
hasnot "$D/b.klar" "consdemo: add=" "B: counter-proof: consumer never ran"
hasnot "$D/b.klar" "EXCEPTION" "B: no kernel exception"
has "$D/c.klar" "drvstore: bind consother -> " "C: consumer bound to the serial device"
has "$D/c.klar" "provother: init" "C: wrong provider was loaded"
has "$D/c.klar" "fail: symbol" "C: provider lacks the symbol: R_SYM"
hasnot "$D/c.klar" "consdemo: add=" "C: counter-proof: consumer never ran"
awk '/provother: init/{i=NR} /provother: exit/{e=NR} END{exit !(i>0 && e>i)}' "$D/c.klar" && ok "C: failed bind drops the provider again" || bad "C: provider leaked after failed bind"
awk '/==RETRY==/{f=1} f' "$D/c.klar" > "$D/c.retry"
count_is "$D/c.retry" "provother: init" "C: every retry loads the provider afresh (no slot leak)" 2
count_is "$D/c.retry" "provother: exit" "C: every retry drops the provider again" 2
hasnot "$D/c.klar" "EXCEPTION" "C: no kernel exception"
fin
