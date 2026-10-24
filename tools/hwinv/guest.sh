#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hwinv/guest.sh -- /bin/hwinv in a real guest: IDE baseline, +AHCI, +NVMe, +RAID (megasas), plus a file run.
#   bash tools/hwinv/guest.sh
# Counter-proof: the baseline must NOT report ahci/nvme/raid.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
PROGS="sh cat echo hwinv sysinfo"
mkdir -p "$TMPD/bin"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 && ok "hwinv builds" || { bad "build"; head -20 "$TMPD/b.txt"; echo "HWINV-GUEST: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 && ok "kernel builds" || { bad "kernel"; echo "HWINV-GUEST: $pass passed, $fail failed"; exit 1; }
python3 - "$TMPD/ssdt.aml" <<'EOP'
import sys
dev = b"\x5b\x82\x1e" + b"TPD0" + b"\x08_HID\x0dELAN0000\x00" + b"\x08_CID\x0c\x41\xd0\x0c\x50"
body = b"\x10\x26" + b"\\_SB_" + dev
hdr = b"SSDT" + (36 + len(body)).to_bytes(4, "little") + b"\x02\x00" + b"HWINV " + b"TPDTEST " + b"\x01\x00\x00\x00" + b"INTL" + b"\x20\x20\x20\x20"
t = bytearray(hdr + body)
t[9] = (-sum(t)) & 0xFF
open(sys.argv[1], "wb").write(t)
EOP
cat > "$TMPD/s.sh" <<'EOS'
echo ==ACPI==
cat /proc/acpi
echo ==REPORT==
hwinv
echo ==FILE==
hwinv /tmp/hw.txt
cat /tmp/hw.txt
echo ==INPUT==
cat /proc/inputdevs
echo ==HWCHECK==
sysinfo --hwcheck
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
head -c 8388608 /dev/zero > "$TMPD/extra.img"
runvm() {
    local name=$1; shift
    cp "$TMPD/d.img" "$TMPD/d-$name.img"
    timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$TMPD/k0.img" -m 512 \
        -device qemu-xhci -device usb-kbd -append "osum vfs usb ${WORDS:-} script=sh /t/s.sh;exit" \
        -serial "file:$TMPD/o-$name.txt" -display none -no-reboot \
        -drive "file=$TMPD/d-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$TMPD/o-$name.txt" > "$TMPD/$name.klar"
}
runvm base
runvm ahci -device ich9-ahci,id=ahci -drive "file=$TMPD/extra.img,format=raw,if=none,id=x0" -device ide-hd,drive=x0,bus=ahci.0
runvm nvme -drive "file=$TMPD/extra.img,format=raw,if=none,id=n0" -device nvme,drive=n0,serial=hwinvtest
runvm raid -device megasas,id=raid0
WORDS=fakeraid runvm rst -device ich9-ahci,id=ahci -drive "file=$TMPD/extra.img,format=raw,if=none,id=x0" -device ide-hd,drive=x0,bus=ahci.0
runvm iommu -machine q35,kernel-irqchip=split -device intel-iommu,intremap=on
runvm ssdt -acpitable sig=SSDT,file="$TMPD/ssdt.aml"
WORDS=smpfrueh runvm smp4 -machine q35 -cpu Skylake-Client -smp 4
has "$TMPD/base.klar" "hwinv: version=1" "base: report printed"
has "$TMPD/base.klar" "hwinv: firmware=BIOS" "base: multiboot kernel run is measured as BIOS"
has "$TMPD/base.klar" "hwinv: storage=ide" "base: IDE only"
has "$TMPD/base.klar" "hwinv: storage_verdict=ok" "base: verdict ok"
has "$TMPD/base.klar" "hwinv: gpu=1234:1111 qemu" "base: VGA is the QEMU adapter"
has "$TMPD/base.klar" "hwinv: usb_kbd=1" "base: the usb keyboard is counted"
has "$TMPD/base.klar" "hwinv: wlan=none" "base: no wlan"
has "$TMPD/base.klar" "== pci ==" "base: raw PCI copy"
has "$TMPD/base.klar" "hwinv: wrote " "base: file mode reports the byte count"
hasnot "$TMPD/base.klar" "storage=ahci" "counter-proof: base has no AHCI"
hasnot "$TMPD/base.klar" "storage=nvme" "counter-proof: base has no NVMe in the summary"
hasnot "$TMPD/base.klar" "storage=raid" "counter-proof: base has no RAID in the summary"
has "$TMPD/ahci.klar" "hwinv: storage=ahci+ide" "ahci: controller found next to IDE"
has "$TMPD/nvme.klar" "hwinv: storage=nvme+ide" "nvme: controller found next to IDE"
has "$TMPD/raid.klar" "hwinv: storage=raid+ide" "raid: class 0104 found"
has "$TMPD/raid.klar" "hwinv: storage_verdict=ok" "raid + ide root: a usable disk still exists"
has "$TMPD/base.klar" "tables: DSDT FACP" "base: acpi table list starts with the DSDT and the FADT"
has "$TMPD/base.klar" "APIC" "base: MADT listed"
has "$TMPD/base.klar" "hwinv: acpi_tables=" "base: tables in the summary"
has "$TMPD/base.klar" "hwinv: acpi_i2chid=0" "base: no i2c-hid device"
hasnot "$TMPD/base.klar" "hwinv: pointing=acpi-i2c-hid" "counter-proof: base is not i2c-hid"
hasnot "$TMPD/base.klar" "ELAN0000" "counter-proof: base has no touchpad id"
has "$TMPD/rst.klar" "hwinv: storage_verdict=raid-rst-nvme-hidden" "rst: verdict names the hidden NVMe"
has "$TMPD/rst.klar" "BIOS: set SATA mode to AHCI" "rst: the text names the BIOS setting"
has "$TMPD/rst.klar" "storage: check BIOS: set SATA mode to AHCI" "rst: sysinfo --hwcheck shows the BIOS hint"
hasnot "$TMPD/ahci.klar" "storage_verdict=raid-rst" "counter-proof: plain AHCI has no RST verdict"
hasnot "$TMPD/ahci.klar" "set SATA mode to AHCI" "counter-proof: plain AHCI shows no BIOS hint"
has "$TMPD/ahci.klar" "storage: ok" "ahci: sysinfo --hwcheck storage ok"
hasnot "$TMPD/rst.klar" "EXCEPTION" "rst: no kernel exception with a RAID-class controller"
has "$TMPD/ssdt.klar" "ELAN0000 cid=PNP0C50 x1 \\_SB.TPD0" "ssdt: /proc/acpi lists the touchpad with its CID and path"
has "$TMPD/ssdt.klar" "hwinv: acpi_i2chid=1" "ssdt: one i2c-hid device counted"
has "$TMPD/ssdt.klar" "hwinv: pointing=acpi-i2c-hid" "ssdt: pointing names acpi-i2c-hid"
has "$TMPD/base.klar" "hwinv: iommu=none" "base: no DMAR -> iommu=none"
hasnot "$TMPD/base.klar" "hwinv: iommu=intel-vtd" "counter-proof: base is not intel-vtd"
has "$TMPD/iommu.klar" "hwinv: iommu=intel-vtd" "iommu: q35 intel-iommu reported"
has "$TMPD/iommu.klar" "hwinv: iommu_translation=off" "iommu: translation off"
has "$TMPD/iommu.klar" "== dmar ==" "iommu: raw dmar section"
has "$TMPD/base.klar" "hwinv: cpus_online=1" "base: one core online (hwinv cpus key)"
has "$TMPD/base.klar" "hwinv: kick=on" "base: kick key"
has "$TMPD/base.klar" "== cpus ==" "base: raw cpus section"
has "$TMPD/smp4.klar" "hwinv: cpus_online=4" "smp4: four cores online in hwinv"
has "$TMPD/smp4.klar" "hwinv: cpus_madt=4" "smp4: madt count key"
has "$TMPD/smp4.klar" "hwinv: failed=0" "smp4: failed key"
hasnot "$TMPD/smp4.klar" "hwinv: cpus_online=1" "counter-proof: smp4 is not one core"
has "$TMPD/base.klar" "==INPUT==" "base: input section ran"
has "$TMPD/base.klar" "i2c_ctrls=0 i2c_devs=0 i2c_hung=0" "base: /proc/inputdevs head (no I2C controller in QEMU)"
has "$TMPD/base.klar" "hwinv: i2c_ctrls=0" "base: hwinv key i2c_ctrls"
has "$TMPD/base.klar" "hwinv: hid_devs=" "base: hwinv key hid_devs"
has "$TMPD/base.klar" "== inputdevs ==" "base: raw inputdevs section"
hasnot "$TMPD/base.klar" "hwinv: ctrl0" "counter-proof: controller lines are not keys"
has "$TMPD/base.klar" "hwinv: backlight.source=" "base: backlight source key"
has "$TMPD/base.klar" "hwinv: backlight.percent=" "base: backlight percent key"
has "$TMPD/base.klar" "hwinv: backlight.ext.count=" "base: backlight ext.count key (unknown Fn codes show up here)"
has "$TMPD/base.klar" "== backlight ==" "base: raw backlight section"
n=$(grep -c "^hwinv: " "$TMPD/base.klar"); [ "$n" -ge 28 ] && ok "base: $n hwinv lines (stdout + file copy)" || bad "base: only $n hwinv lines"
echo "HWINV-GUEST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
