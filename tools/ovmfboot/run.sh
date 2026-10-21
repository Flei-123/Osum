#!/bin/bash
# OVMF stick boot gate (HP-12 / HP-4, r1521): the stick must boot to the login screen under UEFI
# (OVMF, q35 and i440fx, usb-storage like the real HP), the ACPI scan must find the RSDP, and
# there must be no exception. Counter-proofs: word `acpiold` (old scan) must crash with
# #PF cr2=0x806000 under OVMF; SeaBIOS boots in both variants.
#
# Variants: usb-ehci, qemu-xhci + usb-storage, NVMe (all under OVMF q35).
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
    case "$bus" in
        ehci) busargs=(-device usb-ehci -device usb-storage,drive=stick) ;;
        xhci) busargs=(-device qemu-xhci -device usb-storage,drive=stick) ;;
        nvme) busargs=(-device nvme,drive=stick,serial=hpstick,bootindex=0) ;;
    esac
    cp "$D/stick.img" "$D/$name.img"
    mcopy -i "$D/$name.img@@$OFF" -o "$conf" ::limine.conf
    local fwargs=()
    if [ "$fw" = uefi ]; then
        cp "$OVMF_VARS" "$D/$name.vars"
        fwargs=(-drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" -drive "if=pflash,format=raw,unit=1,file=$D/$name.vars")
    fi
    timeout $((secs+15)) qemu-system-x86_64 "${KVM[@]}" -machine "$mach" -m 2048 -smp 2 \
        -drive "file=$D/$name.img,format=raw,if=none,id=stick" "${busargs[@]}" \
        "${fwargs[@]}" -serial "file:$D/$name.txt" -display none -no-reboot -pidfile "$D/$name.pid" &
    local i=0
    while [ $i -lt $((secs*5)) ]; do
        grep -aq "glogin: rect\|EXCEPTION" "$D/$name.txt" 2>/dev/null && { sleep 4; break; }
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
echo "== counter-proof: old scan under OVMF =="
boot uold q35 uefi "$D/l_old.conf" 60
grep -aq "EXCEPTION 14 #PF.*cr2=0x806000" "$D/uold.txt" && ok "acpiold: crashes with #PF cr2=0x806000 (the HP-12 bug)" || bad "acpiold: expected #PF cr2=0x806000 under OVMF"
grep -aq "acpi_scan\|acpi.tag" "$D/uold.txt" && ok "acpiold: trace names acpi.tag" || bad "acpiold: trace without acpi.tag"
echo "OVMFBOOT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
