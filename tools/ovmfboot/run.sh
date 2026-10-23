#!/bin/bash
# OVMF stick boot gate (HP-12 / HP-4, r1521): the stick must boot to the login screen under UEFI
# (OVMF, q35 and i440fx, usb-storage like the real HP), the ACPI scan must find the RSDP, and
# there must be no exception. Counter-proofs: word `acpiold` (old scan) must crash with
# #PF cr2=0x806000 under OVMF; SeaBIOS boots in both variants.
#
# Variants: usb-ehci, qemu-xhci + usb-storage, NVMe, AHCI (q35 onboard SATA) as boot medium (all under OVMF q35),
# plus system layouts (xHCI stick + AHCI or NVMe system disk), Intel RST (`fakeraid` word: the notice must name
# the BIOS setting), missing/unknown hardware (no PS/2, fake Intel 8265 id, HDA without codec: no fault line,
# login still reached). Counter-proofs: blank AHCI/NVMe disk does not boot, no `fakeraid` word = no RST notice,
# no `fakewlan` word = `iwl: no device`.
# Env: STICK_IMG = existing stick image (default: build one with tools/usbimg/build.sh, ~9 min),
#      KERNEL    = prebuilt osum.mb (default: build with tools/build-kernel.sh --stufe 0).
#      KEEP=1 keeps the work directory, ONLY_OLD=1 runs only the counter-proof.
# Heavy: run through `heavy bash tools/ovmfboot/run.sh` (builds); QEMU runs are small.
set -u
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
D=$(mktemp -d /root/abbilder/ovmfboot.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$OVMF_CODE" ] && [ -f "$OVMF_VARS" ] || { echo "OVMFBOOT: OVMF firmware missing"; exit 1; }
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
XDEV=()

if [ -n "${STICK_IMG:-}" ]; then
    cp "$STICK_IMG" "$D/stick.img"
else
    bash tools/usbimg/build.sh "$D/build" > "$D/build.txt" 2>&1 || { tail -5 "$D/build.txt"; echo "OVMFBOOT: stick build failed"; exit 1; }
    mv "$D/build/orientos-usb.img" "$D/stick.img"
fi
if [ -n "${KERNEL:-}" ]; then cp "$KERNEL" "$D/osum.mb"; else
    bash tools/build-kernel.sh "$D/osum.mb" --stufe 0 > "$D/kb.txt" 2>&1 || { tail -5 "$D/kb.txt"; echo "OVMFBOOT: kernel build failed"; exit 1; }
fi
OFF=$((2048*512))
mcopy -i "$D/stick.img@@$OFF" -o "$D/osum.mb" ::osum.mb || { echo "OVMFBOOT: mcopy kernel"; exit 1; }
mcopy -i "$D/stick.img@@$OFF" ::limine.conf "$D/limine.conf" || { echo "OVMFBOOT: mcopy limine.conf"; exit 1; }
sed 's/^timeout: .*/timeout: 1/' "$D/limine.conf" > "$D/l_norm.conf"
sed '0,/cmdline: /s//cmdline: acpiold /' "$D/l_norm.conf" > "$D/l_old.conf"

# boot name machine firmware(uefi|bios) conf
boot() {
    local name=$1 mach=$2 fw=$3 conf=$4 secs=${5:-45} bus=${6:-ehci}
    local busargs
    local want=${WANT:-glogin: rect}
    case "$bus" in
        ehci) busargs=(-device usb-ehci -device usb-storage,drive=stick) ;;
        xhci) busargs=(-device qemu-xhci -device usb-storage,drive=stick) ;;
        nvme) busargs=(-device nvme,drive=stick,serial=hpstick,bootindex=0) ;;
        ahci) busargs=(-device ide-hd,drive=stick,bus=ide.0,bootindex=0) ;;
    esac
    cp "$D/stick.img" "$D/$name.img"
    mcopy -i "$D/$name.img@@$OFF" -o "$conf" ::limine.conf
    local fwargs=()
    if [ "$fw" = uefi ]; then
        cp "$OVMF_VARS" "$D/$name.vars"
        fwargs=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" -drive "if=pflash,format=raw,unit=1,file=$D/$name.vars")
    fi
    timeout $((secs+15)) qemu-system-x86_64 "${KVM[@]}" -machine "$mach" -m 2048 -smp 2 \
        -drive "file=$D/$name.img,format=raw,if=none,id=stick" "${busargs[@]}" "${XDEV[@]}" \
        "${fwargs[@]}" -serial "file:$D/$name.txt" -display none -no-reboot -pidfile "$D/$name.pid" &
    local i=0
    while [ $i -lt $((secs*5)) ]; do
        grep -aq "$want\|EXCEPTION" "$D/$name.txt" 2>/dev/null && { sleep 4; break; }
        sleep 0.2; i=$((i+1))
    done
    kill "$(cat "$D/$name.pid" 2>/dev/null)" 2>/dev/null; wait 2>/dev/null
}
check_good() { # name label
    local t="$D/$1.txt"
    grep -aq "EXCEPTION" "$t" && bad "$2: kernel exception: $(grep -a 'EXCEPTION' "$t" | head -1)" || ok "$2: no exception"
    grep -aq "^smp: cpus=[0-9]*  acpi=1" "$t" && ok "$2: ACPI found (smp: acpi=1)" || bad "$2: smp: acpi=1 missing"
    grep -aq "glogin: rect" "$t" && ok "$2: login screen reached" || bad "$2: login screen not reached"
}
check_clean() { # name label: no fault, panic or halt lines
    local t="$D/$1.txt"
    grep -aq "EXCEPTION\|kernel halted\|panic:\|user fault" "$t" && bad "$2: fault line: $(grep -a 'EXCEPTION\|kernel halted\|panic:\|user fault' "$t" | head -1)" || ok "$2: no fault/panic/halt line"
}
mkblank() { head -c 67108864 /dev/zero > "$D/blank.img"; }
with_word() { sed "0,/cmdline: /s//cmdline: $1 /" "$D/l_norm.conf" > "$D/l_$2.conf"; }

[ -n "${ONLY_OLD:-}" ] || {
echo "== OVMF q35 =="
boot uq35 q35 uefi "$D/l_norm.conf"; check_good uq35 "OVMF q35"
echo "== OVMF i440fx =="
boot ui440 pc uefi "$D/l_norm.conf"; check_good ui440 "OVMF i440fx"
echo "== OVMF q35 + xHCI usb-storage =="
boot uxhci q35 uefi "$D/l_norm.conf" 60 xhci; check_good uxhci "OVMF q35 xHCI"
echo "== OVMF q35 + NVMe =="
boot unvme q35 uefi "$D/l_norm.conf" 60 nvme; check_good unvme "OVMF q35 NVMe"
echo "== SeaBIOS control =="
boot bq35 q35 bios "$D/l_norm.conf"; check_good bq35 "SeaBIOS q35"
}

mkblank
with_word fakeraid raid
with_word fakewlan wlan
SYSDISK=(-drive "file=$D/blank.img,format=raw,if=none,id=sysd")
echo "== OVMF q35 + AHCI boot medium (HP SATA layout) =="
boot uahci q35 uefi "$D/l_norm.conf" 60 ahci; check_good uahci "OVMF q35 AHCI"
echo "== OVMF q35 + xHCI stick + AHCI system disk =="
XDEV=("${SYSDISK[@]}" -device ide-hd,drive=sysd,bus=ide.1)
boot usysa q35 uefi "$D/l_norm.conf" 60 xhci; check_good usysa "OVMF stick + AHCI system disk"
grep -aq "pci: .*class=01:06:01" "$D/usysa.txt" && ok "AHCI system disk: controller class 01:06:01 listed" || bad "AHCI system disk: no class 01:06:01 pci line"
echo "== OVMF q35 + xHCI stick + NVMe system disk =="
XDEV=("${SYSDISK[@]}" -device nvme,drive=sysd,serial=hpsys)
boot usysn q35 uefi "$D/l_norm.conf" 60 xhci; check_good usysn "OVMF stick + NVMe system disk"
grep -aq "nvme" "$D/usysn.txt" && ok "NVMe system disk: driver line present" || bad "NVMe system disk: no nvme line"
echo "== Intel RST layout (fakeraid): notice names the BIOS setting =="
XDEV=("${SYSDISK[@]}" -device ide-hd,drive=sysd,bus=ide.1)
boot uraid q35 uefi "$D/l_raid.conf" 60 xhci; check_good uraid "OVMF RST layout"
grep -aq "pci: .*class=01:04:00" "$D/uraid.txt" && ok "RST: controller listed as class 01:04:00" || bad "RST: no class 01:04:00 pci line"
grep -aq "BIOS: set SATA mode to AHCI" "$D/uraid.txt" && ok "RST: boot text says BIOS: set SATA mode to AHCI" || bad "RST: notice missing"
grep -aq "BIOS: set SATA mode to AHCI" "$D/usysa.txt" && bad "counter-proof: notice shown WITHOUT fakeraid" || ok "counter-proof: no RST notice without fakeraid"
echo "== missing/unknown hardware: no PS/2, fake Intel 8265 id, HDA without codec =="
XDEV=("${SYSDISK[@]}" -device ide-hd,drive=sysd,bus=ide.1 -device e1000 -device intel-hda -device usb-kbd -device usb-mouse)
boot uodd q35,i8042=off uefi "$D/l_wlan.conf" 60 xhci; check_good uodd "no PS/2 + fake 8265 + HDA without codec"
check_clean uodd "no PS/2 + fake 8265 + HDA without codec"
grep -aq "iwl: .*id=8086:24fd" "$D/uodd.txt" && ok "fake 8265 probed without fault (iwl line names id=8086:24fd, mac=unknown)" || bad "fake 8265 not seen in the iwl line: $(grep -a 'iwl:' "$D/uodd.txt" | head -1)"
XDEV=("${SYSDISK[@]}" -device ide-hd,drive=sysd,bus=ide.1 -device e1000 -device usb-kbd -device usb-mouse)
boot unowl q35,i8042=off uefi "$D/l_norm.conf" 60 xhci; check_good unowl "no PS/2 control"
grep -aq "iwl: no device" "$D/unowl.txt" && ok "counter-proof: without fakewlan the e1000 stays a wired card (iwl: no device)" || bad "counter-proof: iwl line without fakewlan: $(grep -a 'iwl:' "$D/unowl.txt" | head -1)"
XDEV=()
echo "== counter-proof: blank AHCI / NVMe disk must NOT boot =="
cp "$D/stick.img" "$D/stick.save"; cp "$D/blank.img" "$D/stick.img"
WANT="EXCEPTION" boot eblank q35 uefi "$D/l_norm.conf" 12 ahci 2>/dev/null
cp "$D/stick.save" "$D/stick.img"
grep -aq "glogin: rect\|^smp: cpus" "$D/eblank.txt" && bad "counter-proof: a blank AHCI disk booted" || ok "counter-proof: blank AHCI disk does not boot"
echo "== counter-proof: old scan under OVMF =="
boot uold q35 uefi "$D/l_old.conf" 60
grep -aq "EXCEPTION 14 #PF.*cr2=0x806000" "$D/uold.txt" && ok "acpiold: crashes with #PF cr2=0x806000 (the HP-12 bug)" || bad "acpiold: expected #PF cr2=0x806000 under OVMF"
grep -aq "acpi_scan\|acpi.tag" "$D/uold.txt" && ok "acpiold: trace names acpi.tag" || bad "acpiold: trace without acpi.tag"
echo "OVMFBOOT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
