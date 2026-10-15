#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sysinfo/run.sh -- E1: THE SYSTEM REPORT (/bin/sysinfo), MEASURED.
#
#   bash tools/sysinfo/run.sh
#
# Real guest under QEMU with a KNOWN serial number in SMBIOS
# (-smbios type=1,serial=SECRET-SERIAL-4711, uuid=...):
#   - the report has its sections (system, machine, cpu, memory, uptime,
#     load, mounts, crash reports) and the machine name from SMBIOS
#   - the serial, the UUID and the fingerprint are NOT in it
#   - COUNTER-PROBE: `hwid -r` in the same guest DOES print the serial,
#     so a green "not in the report" is not just an empty machine
#   - the report is a file when redirected (the export button)
#   - hardware tables: /proc/pci (VGA 1234:1111, host bridge), /proc/usb (a
#     usb-kbd on qemu-xhci with its driver), /proc/firmware (BIOS, secure boot
#     honest "unknown", framebuffer); the report has sections firmware, gpu,
#     pci, usb; gpu lists ONLY display controllers (class 03)
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
mkdir -p "$TMPD/bin"
PROGS="sh cat echo sysinfo hwid"
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
    && ok "sysinfo builds" || { bad "build"; head -20 "$TMPD/b.txt"; has "$TMPD/pci.txt" "0300 1234:1111" "/proc/pci: the QEMU VGA adapter (class 0300, 1234:1111)"
has "$TMPD/pci.txt" "0600 8086:1237" "/proc/pci: the host bridge (class 0600, 8086:1237)"
has "$TMPD/pci.txt" "irq=" "/proc/pci: lines end with the interrupt line"
has "$TMPD/usb.txt" "0627:0001" "/proc/usb: the usb-kbd (0627:0001)"
has "$TMPD/usb.txt" "driver=keyboard" "/proc/usb: the keyboard driver is named"
has "$TMPD/usb.txt" "speed=" "/proc/usb: the speed is named"
has "$TMPD/fw.txt" "boot_mode: BIOS" "/proc/firmware: QEMU SeaBIOS is measured as BIOS"
has "$TMPD/fw.txt" "secure_boot: unknown" "/proc/firmware: secure boot is honest 'unknown', not invented"
has "$TMPD/fw.txt" "framebuffer: " "/proc/firmware: the framebuffer line"
awk '/^== gpu ==/{f=1;next} /^== pci ==/{f=0} f' "$TMPD/rep.txt" | grep -v '^$' > "$TMPD/gpu.txt"
has "$TMPD/gpu.txt" "0300 1234:1111" "report gpu section: the display adapter"
hasnot "$TMPD/gpu.txt" "0600 8086:1237" "report gpu section: ONLY display controllers (no host bridge)"
has "$TMPD/rep.txt" "boot_mode: BIOS" "report: firmware section shows the boot mode"
echo "SYSINFO: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel"; has "$TMPD/pci.txt" "0300 1234:1111" "/proc/pci: the QEMU VGA adapter (class 0300, 1234:1111)"
has "$TMPD/pci.txt" "0600 8086:1237" "/proc/pci: the host bridge (class 0600, 8086:1237)"
has "$TMPD/pci.txt" "irq=" "/proc/pci: lines end with the interrupt line"
has "$TMPD/usb.txt" "0627:0001" "/proc/usb: the usb-kbd (0627:0001)"
has "$TMPD/usb.txt" "driver=keyboard" "/proc/usb: the keyboard driver is named"
has "$TMPD/usb.txt" "speed=" "/proc/usb: the speed is named"
has "$TMPD/fw.txt" "boot_mode: BIOS" "/proc/firmware: QEMU SeaBIOS is measured as BIOS"
has "$TMPD/fw.txt" "secure_boot: unknown" "/proc/firmware: secure boot is honest 'unknown', not invented"
has "$TMPD/fw.txt" "framebuffer: " "/proc/firmware: the framebuffer line"
awk '/^== gpu ==/{f=1;next} /^== pci ==/{f=0} f' "$TMPD/rep.txt" | grep -v '^$' > "$TMPD/gpu.txt"
has "$TMPD/gpu.txt" "0300 1234:1111" "report gpu section: the display adapter"
hasnot "$TMPD/gpu.txt" "0600 8086:1237" "report gpu section: ONLY display controllers (no host bridge)"
has "$TMPD/rep.txt" "boot_mode: BIOS" "report: firmware section shows the boot mode"
echo "SYSINFO: $pass passed, $fail failed"; exit 1; }
cat > "$TMPD/s.sh" <<'EOS'
echo ==REPORT==
sysinfo
echo ==HWID==
hwid -r
echo ==PCI==
cat /proc/pci
echo ==USB==
cat /proc/usb
echo ==FW==
cat /proc/firmware
echo ==FILE==
sysinfo > /tmp/report.txt
cat /tmp/report.txt
echo ==HW==
sysinfo --hwcheck
echo ==HWF==
sysinfo --hwcheck --export /tmp/hw.txt > /dev/null
cat /tmp/hw.txt
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ /var/crash/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -smbios "type=1,manufacturer=FleiTest,product=Probe-One,serial=SECRET-SERIAL-4711,uuid=8c1b2f4e-1111-4222-8333-444455556666" \
    -device qemu-xhci -device usb-kbd \
    -append "osum vfs usb script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/o.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/o.txt" > "$TMPD/o.klar"
part "$TMPD/o.klar" REPORT HWID > "$TMPD/rep.txt"
part "$TMPD/o.klar" HWID PCI > "$TMPD/hw.txt"
part "$TMPD/o.klar" FILE HW > "$TMPD/file.txt"
part "$TMPD/o.klar" HW HWF > "$TMPD/hwc.txt"
part "$TMPD/o.klar" HWF END > "$TMPD/hwf.txt"
part "$TMPD/o.klar" PCI USB > "$TMPD/pci.txt"
part "$TMPD/o.klar" USB FW > "$TMPD/usb.txt"
part "$TMPD/o.klar" FW FILE > "$TMPD/fw.txt"
for sec in "== system ==" "== machine ==" "== cpu ==" "== memory ==" "== uptime ==" "== load ==" "== mounts ==" "== firmware ==" "== gpu ==" "== pci ==" "== usb ==" "== crash reports =="; do
    has "$TMPD/rep.txt" "$sec" "report has section $sec"
done
has "$TMPD/rep.txt" "FleiTest" "the SMBIOS manufacturer is in the report"
hasnot "$TMPD/rep.txt" "SECRET-SERIAL-4711" "the serial number is NOT in the report"
hasnot "$TMPD/rep.txt" "8c1b2f4e" "the UUID is NOT in the report"
hasnot "$TMPD/rep.txt" "fingerprint" "no fingerprint in the report"
has "$TMPD/rep.txt" "identity lines left out of this report:" "the report says that identity lines were left out"
has "$TMPD/hw.txt" "SECRET-SERIAL-4711" "COUNTER-PROBE: hwid -r prints the serial in the same guest"
has "$TMPD/file.txt" "OrientOS system report" "redirected: the report is a file (export)"
hasnot "$TMPD/file.txt" "SECRET-SERIAL-4711" "the exported file has no serial either"
has "$TMPD/pci.txt" "0300 1234:1111" "/proc/pci: the QEMU VGA adapter (class 0300, 1234:1111)"
has "$TMPD/pci.txt" "0600 8086:1237" "/proc/pci: the host bridge (class 0600, 8086:1237)"
has "$TMPD/pci.txt" "irq=" "/proc/pci: lines end with the interrupt line"
has "$TMPD/usb.txt" "0627:0001" "/proc/usb: the usb-kbd (0627:0001)"
has "$TMPD/usb.txt" "driver=keyboard" "/proc/usb: the keyboard driver is named"
has "$TMPD/usb.txt" "speed=" "/proc/usb: the speed is named"
has "$TMPD/fw.txt" "boot_mode: BIOS" "/proc/firmware: QEMU SeaBIOS is measured as BIOS"
has "$TMPD/fw.txt" "secure_boot: unknown" "/proc/firmware: secure boot is honest 'unknown', not invented"
has "$TMPD/fw.txt" "framebuffer: " "/proc/firmware: the framebuffer line"
awk '/^== gpu ==/{f=1;next} /^== pci ==/{f=0} f' "$TMPD/rep.txt" | grep -v '^$' > "$TMPD/gpu.txt"
has "$TMPD/gpu.txt" "0300 1234:1111" "report gpu section: the display adapter"
hasnot "$TMPD/gpu.txt" "0600 8086:1237" "report gpu section: ONLY display controllers (no host bridge)"
has "$TMPD/rep.txt" "boot_mode: BIOS" "report: firmware section shows the boot mode"
has "$TMPD/hwc.txt" "OrientOS hardware check" "hwcheck: header"
has "$TMPD/hwc.txt" "display: ok 0300 1234:1111" "hwcheck: the QEMU VGA is the display"
has "$TMPD/hwc.txt" "keyboard: ok usb" "hwcheck: the usb-kbd is the keyboard"
has "$TMPD/hwc.txt" "audio: missing" "hwcheck: no audio device in this VM -> missing (not invented)"
has "$TMPD/hwc.txt" "wlan: missing" "hwcheck: no wlan device in this VM -> missing"
has "$TMPD/hwc.txt" "sends nothing anywhere" "hwcheck: says it sends nothing"
has "$TMPD/hwf.txt" "display: ok 0300 1234:1111" "hwcheck --export: the local file has the same report"
hasnot "$TMPD/hwc.txt" "SECRET-SERIAL-4711" "hwcheck: no serial number"
echo "SYSINFO: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
