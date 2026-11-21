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
hasre() { grep -qaE -- "$2" "$1" && ok "$3" || bad "$3 -- /$2/ missing"; }
if [ -n "${HWPROFILE_WORKDIR:-}" ]; then D=$HWPROFILE_WORKDIR; mkdir -p "$D"; else D=$(mktemp -d); trap 'rm -rf "$D"' EXIT; fi
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
. tools/lib/firnenv.sh
fin() { echo "HWPROFILE: $pass passed, $fail failed"; [ "$fail" -eq 0 ]; exit $?; }
bash tools/module/build.sh "$D/edudemo.omod" --quelle module/store/edudemo.fi > "$D/m.txt" 2>&1 && ok "demo module builds and is signed" || { bad "module"; tail -5 "$D/m.txt"; fin; }
PROGS="sh cat echo ls sync drvctl hwprofile"
mkdir -p "$D/bin" "$D/pool-ok" "$D/pool-mutant"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; fin; }
if [ -n "${HWPROFILE_KERNEL:-}" ]; then cp "$HWPROFILE_KERNEL" "$D/k0.img"; ok "kernel supplied"; else
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; fin; }; fi

printf 'firmware blob for the pvpanic test device\n' > "$D/pvpanic.bin"
FWHASH=$(sha256sum "$D/pvpanic.bin" | cut -d' ' -f1)
MK="$D/edudemo.omod"
mkp() { local pool=$1; shift; python3 tools/drvstore/mkpkg.py build "$pool" --module "$MK" "$@" > /dev/null; }
build_pool() {
    local pool=$1 eu=$2
    mkp "$pool" --name edudemo --match "pci $eu"
    mkp "$pool" --name testdev --match "pci 1b36:0005"
    mkp "$pool" --name panicfw --match "pci 1b36:0011" --fw "pvpanic.bin:$FWHASH"
    mkp "$pool" --name evilserial --match "pci 1b36:0002" --bad-sig
    mkp "$pool" --name unrelated --match "pci 8086:ffff"
}
build_pool "$D/pool-ok" 1234:11e8
build_pool "$D/pool-mutant" 1234:11e9

pool_files() {
    local pool=$1 fw=$2 files="/lib/driverpool/"
    for p in $(ls "$pool"); do
        files="$files /lib/driverpool/$p/"
        for f in $(ls "$pool/$p"); do files="$files /lib/driverpool/$p/$f=$pool/$p/$f"; done
    done
    [ "$fw" = fw ] && files="$files /lib/driverpool/panicfw/pvpanic.bin=$D/pvpanic.bin"
    echo "$files"
}
mkimg() {
    local name=$1; shift
    bash tools/mkfsfi/mkfs.sh build "$D/d-$name.img" 20000 /lib/ /lib/drivers/ \
        "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
        /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
        $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
        "/t/s.sh=$D/s.sh" "/t/r.sh=$D/r.sh" "$@" > "$D/mkfs-$name.txt" 2>&1 || tail -3 "$D/mkfs-$name.txt"
}
runvm() {
    local name=$1 script=$2; shift 2
    timeout 240 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -append "osum vfs script=sh $script;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}

cat > "$D/s.sh" <<'EOS'
echo ==SCAN==
hwprofile scan
echo ==STAGE==
hwprofile stage --prune
echo ==PROFILE==
cat /etc/hwprofile
echo ==UNKNOWN==
cat /etc/hwunknown
echo ==DRIVERS==
ls /lib/drivers
echo ==FIRMWARE==
ls /lib/firmware
echo ==POOL==
ls /lib/driverpool
sync
echo ==END==
EOS
cat > "$D/r.sh" <<'EOS'
echo ==REBOOT==
cat /etc/hwprofile
drvctl list
cat /proc/drivers
echo ==REND==
EOS

MACHINE_A=(-machine q35 -device edu -device pvpanic-pci -device pci-serial)
MACHINE_B=(-machine pc -device pci-testdev -device pci-serial)
mkimg a1 $(pool_files "$D/pool-ok" nofw)
runvm a1 /t/s.sh "${MACHINE_A[@]}"
mkimg a2 $(pool_files "$D/pool-ok" fw)
runvm a2 /t/s.sh "${MACHINE_A[@]}"
cp "$D/d-a2.img" "$D/d-a2r.img"
runvm a2r /t/r.sh "${MACHINE_A[@]}"
mkimg b $(pool_files "$D/pool-ok" nofw)
runvm b /t/s.sh "${MACHINE_B[@]}"
mkimg m $(pool_files "$D/pool-mutant" nofw)
runvm m /t/s.sh "${MACHINE_A[@]}"
mkimg e
runvm e /t/s.sh "${MACHINE_A[@]}"

for n in a1 a2 b m e; do has "$D/$n.klar" "==END==" "$n: script ran to the end"; hasnot "$D/$n.klar" "EXCEPTION" "$n: no kernel exception"; done
has "$D/a2r.klar" "==REND==" "a2r: reboot script ran to the end"

echo "== machine A (q35: edu + pvpanic + pci-serial), firmware blob absent =="
has "$D/a1.klar" "hwprofile 1" "a1: profile header"
hasre "$D/a1.klar" "^machine manufacturer=.* product=.* board=" "a1: machine line (DMI)"
hasre "$D/a1.klar" "^storage nvme=[0-9]+ ahci=[0-9]+ raid=[0-9]+ vmd=[0-9]+ warn=" "a1: storage line"
hasre "$D/a1.klar" "dev pci [0-9a-f:.]+ 1234:11e8 .*status=staged .*pkg=edudemo" "a1: edu matched to the pool package"
hasre "$D/a1.klar" "dev pci [0-9a-f:.]+ 1b36:0011 .*status=firmware-missing .*pkg=panicfw fw=pvpanic.bin" "a1: missing firmware reported"
hasre "$D/a1.klar" "dev pci [0-9a-f:.]+ 1b36:0002 .*status=missing" "a1: bad-signature package never matches (device stays missing)"
hasre "$D/a1.klar" "dev pci [0-9a-f:.]+ 8086:10d3 .*status=driver .*src=builtin" "a1: built-in driver recognised"
hasre "$D/a1.klar" "dev pci [0-9a-f:.]+ 8086:29c0 .*status=infra" "a1: host bridge counted as infrastructure"
hasre "$D/a1.klar" "^summary devices=[0-9]+ driver=[0-9]+ staged=1 missing=2 firmware-missing=1 .*pool=5" "a1: summary counts"
hasre "$D/a1.klar" "hwprofile: staged 2 failed 0" "a1: two packages staged"
hasre "$D/a1.klar" " edudemo/" "a1: edudemo copied to /lib/drivers"
hasre "$D/a1.klar" " panicfw/" "a1: panicfw copied to /lib/drivers"
hasnot "$D/a1.klar" " testdev/" "a1: package for absent hardware not copied"
echo "== unknown export =="
has "$D/a1.klar" "hwunknown 1" "a1: unknown export header"
hasre "$D/a1.klar" "^dev pci [0-9a-f:.]+ 1b36:0002 .*status=missing" "a1: unmatched device exported"

echo "== machine A, firmware blob present =="
hasre "$D/a2.klar" "dev pci [0-9a-f:.]+ 1b36:0011 .*status=staged .*pkg=panicfw" "a2: firmware present -> staged"
hasre "$D/a2.klar" " pvpanic.bin" "a2: firmware copied to /lib/firmware"
hasre "$D/a2.klar" "summary devices=[0-9]+ driver=[0-9]+ staged=2 missing=2 firmware-missing=0" "a2: summary counts"

echo "== the installed system after a restart =="
has "$D/a2r.klar" "hwprofile 1" "a2r: /etc/hwprofile survives the restart"
hasre "$D/a2r.klar" "pkg edudemo version=1 rank=[0-9]+ sig=ok" "a2r: package signed and valid on the installed disk"
hasre "$D/a2r.klar" "pci [0-9a-fx:.]+ 0x1234:0x11e8 .*drv=edudemo src=store bind=bound" "a2r: staged driver binds at the next boot"
hasre "$D/a2r.klar" "pci [0-9a-fx:.]+ 0x1b36:0x0011 .*drv=panicfw src=store bind=bound" "a2r: second staged driver binds"
hasnot "$D/a2r.klar" "pkg testdev" "a2r: only matching packages travelled to the disk"
hasnot "$D/a2r.klar" "pkg evilserial" "a2r: bad package not copied"

echo "== machine B (pc: pci-testdev + pci-serial) =="
hasre "$D/b.klar" "dev pci [0-9a-f:.]+ 1b36:0005 .*status=staged .*pkg=testdev" "b: other hardware -> other package"
hasnot "$D/b.klar" "1234:11e8" "b: edu absent from the profile"
hasre "$D/b.klar" " testdev/" "b: testdev copied"
hasnot "$D/b.klar" " edudemo/" "b: edudemo not copied (profiles differ)"
hasnot "$D/b.klar" " panicfw/" "b: panicfw not copied"
hasre "$D/b.klar" "summary devices=[0-9]+ driver=[0-9]+ staged=1 missing=2 firmware-missing=0" "b: summary counts"

echo "== counter-proofs =="
hasre "$D/m.klar" "dev pci [0-9a-f:.]+ 1234:11e8 .*status=unknown" "mutant: no match -> edu stays unmatched"
if grep -qaE "1234:11e8 .*status=staged" "$D/m.klar"; then bad "mutant: gate would not notice a missing match"; else ok "mutant: the staged-check of the gate goes red without a match"; fi
hasnot "$D/m.klar" " edudemo/" "mutant: nothing copied without a match"
hasre "$D/e.klar" "pool=0" "empty pool: nothing to stage, no crash"
hasre "$D/e.klar" "hwprofile: staged 0 failed 0" "empty pool: zero staged"
hasre "$D/e.klar" "dev pci [0-9a-f:.]+ 1234:11e8 .*status=unknown" "empty pool: device stays unmatched"
fin
