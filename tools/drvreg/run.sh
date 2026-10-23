#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/drvreg/run.sh -- QEMU gate: /proc/drivers (registry) + /proc/dmar (VT-d measure), with counter-proofs.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there" || ok "$3"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh cat echo"
mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 $PROGS > "$D/b.txt" 2>&1 && ok "programs build" || { bad "programs"; head -10 "$D/b.txt"; echo "DRVREG: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$D/k0.img" --stufe 0 > "$D/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; tail -5 "$D/k.txt"; echo "DRVREG: $pass passed, $fail failed"; exit 1; }
cat > "$D/s.sh" <<'EOS'
echo ==DRIVERS==
cat /proc/drivers
echo ==DMAR==
cat /proc/dmar
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$D/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$D/bin/$p.elf"; done) \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || tail -3 "$D/mkfs.txt"
head -c 8388608 /dev/zero > "$D/extra.img"
runvm() {
    local name=$1; shift
    cp "$D/d.img" "$D/d-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k0.img" -m 512 \
        -device qemu-xhci -append "osum vfs usb script=sh /t/s.sh;exit" \
        -serial "file:$D/o-$name.txt" -display none -no-reboot \
        -drive "file=$D/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/o-$name.txt" > "$D/$name.klar"
}
runvm base
runvm nvme -drive "file=$D/extra.img,format=raw,if=none,id=n0" -device nvme,drive=n0,serial=drvtest
runvm iommu -machine q35,kernel-irqchip=split -device intel-iommu,intremap=on
has "$D/base.klar" "# name bus match found state err" "base: /proc/drivers header"
has "$D/base.klar" "xhci pci *:*/0c03.30 found=1" "base: xhci row found once"
has "$D/base.klar" "nvme pci *:*/0108 found=0 state=absent" "base: nvme row absent"
has "$D/base.klar" "i2c-hid acpi PNP0C50 found=?" "base: acpi row registered"
has "$D/base.klar" "# unclaimed=" "base: unclaimed summary"
has "$D/base.klar" "drv: registry rows=25" "base: boot line"
hasnot "$D/base.klar" "nvme pci *:*/0108 found=1" "counter-proof: base has no nvme"
has "$D/nvme.klar" "nvme pci *:*/0108 found=1" "nvme: row found"
hasnot "$D/nvme.klar" "nvme pci *:*/0108 found=0" "counter-proof: nvme run is not absent"
has "$D/base.klar" "dmar: none" "base: no DMAR table"
hasnot "$D/base.klar" "dmar: present" "counter-proof: base has no present line"
has "$D/iommu.klar" "dmar: present haw=" "iommu: DMAR present"
has "$D/iommu.klar" "dmar: drhd seg=0 base=0xfed90000" "iommu: DRHD base"
has "$D/iommu.klar" "dmar: unit 0 base=0xfed90000 ver=0x" "iommu: unit registers read"
has "$D/iommu.klar" "translation=off" "iommu: translation off (not enabled by us)"
hasnot "$D/iommu.klar" "translation=on" "counter-proof: nothing enabled the IOMMU"
hasnot "$D/iommu.klar" "EXCEPTION" "iommu: no kernel exception"
hasnot "$D/base.klar" "EXCEPTION" "base: no kernel exception"
echo "DRVREG: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
