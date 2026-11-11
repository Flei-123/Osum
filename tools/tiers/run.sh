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
. tools/lib/tmpdir.sh
D=$(mktemp -d); osum_tmp_guard "" "$D"
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
MK="python3 -I tools/drvstore/mkpkg.py"
NATIVE_DIRS="kernel boot lib module tools/build-kernel.sh tools/mkfsfi tools/sync tools/module tools/drvstore tools/usbimg"
NEEDLE='linuxkpi|lkpi|compat/linuxkpi|vermagic=|Linux version'
IMPORT_RE='^import +.*(compat|linuxkpi|lkpi)'
scan_native() { grep -rIlE -- "$NEEDLE" "$@" 2>/dev/null | wc -l; }
fin() { echo "TIERS: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }

[ -d compat/linuxkpi ] && ok "compat code lives under compat/linuxkpi" || bad "compat/linuxkpi missing"
[ ! -e tools/linuxkpi ] && [ ! -e kernel/linuxkpi ] && ok "no second compat location" || bad "compat code outside compat/"
for f in fetch.sh pack.sh gate.sh sources.tsv; do [ -e "compat/linuxkpi/$f" ] && ok "compat/linuxkpi/$f present" || bad "compat/linuxkpi/$f missing"; done
[ "$(find compat -name '*.fi' | wc -l)" -eq 0 ] && ok "compat tree holds no Firn kernel code" || bad "Firn files under compat/"
n=$(scan_native $NATIVE_DIRS)
[ "$n" -eq 0 ] && ok "native tree never references compat" || { bad "native tree references compat ($n files)"; grep -rIlE -- "$NEEDLE" $NATIVE_DIRS | head -5; }
n=$(grep -rIE "$IMPORT_RE" kernel lib module 2>/dev/null | wc -l)
[ "$n" -eq 0 ] && ok "no Firn import of a compat module" || bad "$n Firn imports of compat modules"
grep -rIqE 'tools/drvstore/mkpkg.py' compat && ok "dependency direction: compat uses the native package tool" || bad "compat does not use native tools"
mkdir -p "$D/probe/kernel"; cp kernel/bus/drvinf.fi "$D/probe/kernel/"
[ "$(cd "$D/probe" && scan_native kernel)" -eq 0 ] && ok "baseline: clean copy not flagged" || bad "clean copy flagged"
printf 'fn lkpi_init() {}\n' >> "$D/probe/kernel/drvinf.fi"
[ "$(cd "$D/probe" && scan_native kernel)" -eq 1 ] && ok "counter-proof: injected compat reference detected" || bad "injected reference not detected"
printf 'import compat.shim\n' > "$D/probe/kernel/x.fi"
[ "$(cd "$D/probe" && grep -rIE "$IMPORT_RE" kernel | wc -l)" -eq 1 ] && ok "counter-proof: injected compat import detected" || bad "injected import not detected"

. tools/lib/tiers.sh
[ "$(DRIVER_TIERS= bash -c '. tools/lib/tiers.sh; echo $DRIVER_TIERS')" = native ] && ok "switch: DRIVER_TIERS defaults to native" || bad "default is not native"
(DRIVER_TIERS=bogus tiers_validate) >/dev/null 2>&1; [ $? -eq 2 ] && ok "switch: invalid DRIVER_TIERS refused" || bad "invalid DRIVER_TIERS accepted"
(DRIVER_TIERS=native+compat tiers_validate) && ok "switch: native+compat accepted" || bad "native+compat refused"
printf 'OSUMMOD-fake' > "$D/fake.omod"; printf 'lkpi_marker_payload' > "$D/lkpi-marker.bin"
$MK build "$D/pk" --name lkpi-fake --module "$D/fake.omod" --tier compat --match "pci 1234:11e8" >/dev/null
cp "$D/lkpi-marker.bin" "$D/pk/lkpi-fake/lkpi-marker.bin"
mkdir -p "$D/o1" "$D/o2"
a1=$(DRIVER_TIERS=native COMPAT_PACKAGES="$D/pk" USBIMG_EXTRA= tiers_stage_args "$D/o1")
a2=$(DRIVER_TIERS=native+compat COMPAT_PACKAGES="$D/pk" USBIMG_EXTRA= tiers_stage_args "$D/o2")
[ "$(cat "$D/o1/drvstore.conf")" = "tiers=native" ] && ok "native: image gets tiers=native" || bad "native conf wrong"
[ "$(cat "$D/o2/drvstore.conf")" = "tiers=native+compat" ] && ok "native+compat: image gets tiers=native+compat" || bad "compat conf wrong"
echo "$a1" | grep -q 'lkpi' && bad "native: compat package staged" || ok "native: compat packages never staged, even when offered"
echo "$a2" | grep -q '/lib/drivers/lkpi-fake/driver.inf=' && ok "native+compat: offered compat package staged" || bad "native+compat: package not staged"
a3=$(DRIVER_TIERS=native+compat COMPAT_PACKAGES="$D/pk" USBIMG_EXTRA="/etc/drvstore.conf=x" tiers_stage_args "$D/o2")
echo "$a3" | grep -q '^/etc/drvstore.conf=' && bad "caller conf overridden" || ok "caller-supplied /etc/drvstore.conf respected"
img() { local name=$1; shift; bash tools/mkfsfi/mkfs.sh build "$D/i-$name.img" 8000 /lib/ /etc/ "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"; }
img native $a1
img both $a2
[ -s "$D/i-native.img" ] && [ -s "$D/i-both.img" ] && ok "tier images build" || bad "tier images missing"
grep -qaE -- "$NEEDLE" "$D/i-native.img" && bad "native-only image contains compat file/marker" || ok "native-only image contains no compat file/marker"
grep -qaF lkpi_marker_payload "$D/i-both.img" && ok "counter-proof: compat image carries the marker (scan works)" || bad "marker not found in compat image"
[ "$($MK check "$D/pk/lkpi-fake")" = OK ] && ok "mkpkg: tier=compat package passes check" || bad "mkpkg: tier=compat invalid"
grep -q '^tier=compat' "$D/pk/lkpi-fake/driver.inf" && ok "mkpkg: tier key in the signed manifest" || bad "tier key missing"
$MK build "$D/pk2" --name nt --module "$D/fake.omod" --match "pci 1234:11e8" >/dev/null && ! grep -q '^tier=' "$D/pk2/nt/driver.inf" && ok "mkpkg: package without tier key valid (default native)" || bad "native default broken"
$MK build "$D/pk3" --name bt --module "$D/fake.omod" --tier bogus --match "pci 1234:11e8" >/dev/null 2>&1 && bad "bogus tier accepted" || ok "mkpkg: unknown tier refused"
sed -i 's/^tier=compat/tier=native/' "$D/pk/lkpi-fake/driver.inf"
[[ "$($MK check "$D/pk/lkpi-fake")" == INVALID* ]] && ok "counter-proof: flipping tier breaks the signature" || bad "tier flip not detected"

. tools/lib/firnenv.sh
bash tools/module/build.sh "$D/edudemo.omod" --source module/store/edudemo.fi > "$D/m.txt" 2>&1 && ok "edudemo module builds" || { bad "module"; tail -5 "$D/m.txt"; fin; }
PROGS="sh cat echo drvctl"
mkdir -p "$D/bin" "$D/kp"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; fin; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }
grep -qaE -- "$NEEDLE" "$D/k0.img" && bad "kernel image contains compat marker" || ok "kernel image contains no compat/Linux marker"
cp "$D/k0.img" "$D/dirty.img"; printf 'lkpi_shim_marker vermagic=6.12.101' >> "$D/dirty.img"
grep -qaE -- "$NEEDLE" "$D/dirty.img" && ok "counter-proof: marker in kernel image detected" || bad "kernel marker scan blind"

EM="$D/edudemo.omod"
mkp() { $MK build "$D/kp" --module "$EM" "$@" > /dev/null; }
mkp --name nat --rank 10 --match "pci 1234:11e8" --rights mmio
mkp --name cmp --rank 50 --match "pci 1234:11e8" --rights mmio --tier compat
mkdir -p "$D/ks"
$MK build "$D/ks" --module "$EM" --name nat2 --rank 10 --match "pci 1234:11e8" --tier native > /dev/null
$MK build "$D/ks" --module "$EM" --name cmp2 --rank 50 --match "pci 1234:11e8" --tier compat > /dev/null
FILES="/lib/drivers/"
for p in $(ls "$D/kp"); do
    FILES="$FILES /lib/drivers/$p/"
    for f in $(ls "$D/kp/$p"); do FILES="$FILES /lib/drivers/$p/$f=$D/kp/$p/$f"; done
done
SRCF="/t/src/"
for p in nat2 cmp2; do
    SRCF="$SRCF /t/src/$p/"
    for f in $(ls "$D/ks/$p"); do SRCF="$SRCF /t/src/$p/$f=$D/ks/$p/$f"; done
done
cat > "$D/s.sh" <<'EOS'
echo ==TIERS==
drvctl tiers
cat /proc/drivers
drvctl list
drvctl install /t/src/nat2
drvctl install /t/src/cmp2
drvctl list
echo ==END==
EOS
printf 'tiers=native\n' > "$D/conf-native"
printf 'tiers=native+compat\n' > "$D/conf-both"
mkimg() {
    local name=$1; shift
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" $FILES $SRCF "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
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
mkimg dflt
mkimg nat "/etc/drvstore.conf=$D/conf-native"
mkimg both "/etc/drvstore.conf=$D/conf-both"
runvm dflt
runvm nat
runvm both
for n in dflt nat both; do has "$D/$n.klar" "==END==" "$n: run complete"; hasnot "$D/$n.klar" "EXCEPTION" "$n: no kernel exception"; done
for n in dflt nat; do
    has "$D/$n.klar" "drvstore: pkgs=2 valid=1" "$n: compat package not counted as valid"
    has "$D/$n.klar" "drvstore: pkg cmp rejected 26" "$n: compat package refused by policy (26)"
    has "$D/$n.klar" "drvstore: pkg nat ok" "$n: native package unaffected"
    has "$D/$n.klar" "drv=nat src=store bind=bound" "$n: native driver bound although compat ranks higher"
    hasnot "$D/$n.klar" "drv=cmp" "counter-proof $n: compat driver never bound"
    hasnot "$D/$n.klar" "tiers=native+compat" "$n: no compat tier announced"
    has "$D/$n.klar" "tiers=native" "$n: drvctl tiers reports native"
    has "$D/$n.klar" "pkg cmp version=1 rank=50 sig=ok invalid tier=compat" "$n: drvctl list shows tier=compat, unusable"
    has "$D/$n.klar" "pkg nat version=1 rank=10 sig=ok tier=native" "$n: drvctl list shows tier=native"
    has "$D/$n.klar" "packages=2 valid=1" "$n: drvctl count matches the kernel"
    has "$D/$n.klar" "installed nat2 (active after reboot)" "$n: native package installs"
    has "$D/$n.klar" "drvctl: compat tier refused by policy" "$n: compat install refused"
    hasnot "$D/$n.klar" "installed cmp2" "counter-proof $n: compat package not installed"
    has "$D/$n.klar" "packages=3 valid=2" "$n: only the native install changed the store"
done
has "$D/both.klar" "drvstore: tiers=native+compat" "both: boot line announces the policy"
has "$D/both.klar" "drvstore: pkgs=2 valid=2" "both: compat package valid"
has "$D/both.klar" "drvstore: pkg cmp ok" "both: compat package accepted"
has "$D/both.klar" "drv=cmp src=store bind=bound" "both: compat driver wins by rank"
has "$D/both.klar" "tiers=native+compat" "both: drvctl tiers and /proc/drivers report both tiers"
grep -a "pkg cmp version" "$D/both.klar" | grep -qa invalid && bad "both: compat package marked invalid" || ok "both: compat package not flagged"
has "$D/both.klar" "pkg cmp version=1 rank=50 sig=ok tier=compat" "both: drvctl list shows tier=compat"
has "$D/both.klar" "installed cmp2 (active after reboot)" "both: compat install allowed"
hasnot "$D/both.klar" "refused by policy" "counter-proof both: no refusal"
bash compat/linuxkpi/hostbuild.sh > "$D/lh.txt" 2>&1 && ok "compat/linuxkpi host build, harness and closure mutants green" || { bad "compat/linuxkpi hostbuild"; tail -5 "$D/lh.txt"; }
LINUXKPI_IMAGE="$D/k0.img" bash compat/linuxkpi/gate.sh > "$D/lk.txt" 2>&1 && ok "compat/linuxkpi gate green" || { bad "compat/linuxkpi gate"; tail -5 "$D/lk.txt"; }
fin
