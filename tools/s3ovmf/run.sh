#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/s3/checks.sh

LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
OVMF_CODE=${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}
OVMF_VARS=${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.fd}
SAFE_BASE=${S3OVMF_SAFE_BASE:-0x1600000}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

for w in qemu-system-x86_64 sgdisk mkfs.vfat mcopy mmd socat; do
    command -v "$w" >/dev/null 2>&1 || { echo "S3OVMF: skipped, $w missing"; exit 0; }
done
[ -f "$LIMINE/BOOTX64.EFI" ] || { echo "S3OVMF: skipped, Limine UEFI loader missing ($LIMINE)"; exit 0; }
[ -f "$OVMF_CODE" ] && [ -f "$OVMF_VARS" ] || { echo "S3OVMF: skipped, OVMF firmware missing"; exit 0; }

mkimg() {
    local kernel=$1 img=$2 cmdline=$3 esp="$TMPD/esp.img"
    printf 'timeout: 0\ndefault_entry: 1\n/s3\n    protocol: multiboot1\n    path: boot():/osum.mb\n    cmdline: %s\n' "$cmdline" > "$TMPD/limine.conf"
    rm -f "$img" "$esp"
    dd if=/dev/zero of="$img" bs=1M count=0 seek=48 status=none
    sgdisk --clear --new=1:2048:+40M --typecode=1:EF00 "$img" >/dev/null 2>&1 || return 1
    dd if=/dev/zero of="$esp" bs=1M count=40 status=none
    mkfs.vfat -F 32 "$esp" >/dev/null 2>&1 || return 1
    mmd -i "$esp" ::/EFI ::/EFI/BOOT || return 1
    mcopy -i "$esp" "$LIMINE/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI || return 1
    mcopy -i "$esp" "$TMPD/limine.conf" ::/limine.conf || return 1
    mcopy -i "$esp" "$kernel" ::/osum.mb || return 1
    dd if="$esp" of="$img" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$esp"
}

mon() { echo "$1" | socat - "UNIX-CONNECT:$2" 2>/dev/null | tr -d '\r'; }
vm_status() { mon 'info status' "$1" | grep -ao 'VM status: .*' | head -1; }

run_cycles() {
    local img=$1 log=$2 cycles=$3 wake=$4 smp=${5:-1} machine=${6:-q35}
    local sock="$TMPD/mon.$RANDOM" vars="$TMPD/vars.$RANDOM" pid c i n st
    STATUS1=""; STATUS2=""; AFTER=""
    rm -f "$log"
    cp "$OVMF_VARS" "$vars"
    timeout 150 $QEMU_X86 -machine "$machine" -m 2048 -smp "$smp" \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$vars" \
        -drive "file=$img,format=raw,if=none,id=d" -device ide-hd,drive=d,bus=ide.0,bootindex=0 \
        -serial "file:$log" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    pid=$!
    for c in $(seq 1 "$cycles"); do
        for i in $(seq 1 600); do
            n=$(grep -ac 's3: schlafe' "$log" 2>/dev/null)
            [ "${n:-0}" -ge "$c" ] && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        sleep 1
        st=$(vm_status "$sock")
        if [ "$c" = 1 ]; then STATUS1=$st; else STATUS2=$st; fi
        case $st in *suspended*) ;; *) break ;; esac
        mon system_wakeup "$sock" >/dev/null
        if [ "$wake" = 0 ]; then
            sleep 10
            AFTER=$(vm_status "$sock")
            mon quit "$sock" >/dev/null
            break
        fi
    done
    wait "$pid"; RC=$?
    rm -f "$sock" "$vars"
}

echo "== 1. build: kernel at the default base and at $SAFE_BASE =="
bash tools/build-kernel.sh "$TMPD/k-default" > "$TMPD/b1.txt" 2>&1 \
    && ok "default-base kernel built" || { bad "default-base kernel build"; tail -6 "$TMPD/b1.txt" | sed 's/^/        /'; }
bash tools/build-kernel.sh "$TMPD/k-safe" --base "$SAFE_BASE" > "$TMPD/b2.txt" 2>&1 \
    && ok "safe-base kernel built" || { bad "safe-base kernel build"; tail -6 "$TMPD/b2.txt" | sed 's/^/        /'; }
low=$(readelf -lW "$TMPD/k-safe.elf" 2>/dev/null | awk '$1=="LOAD" {print $3}' | sort | head -1)
[ -n "$low" ] && [ $((low)) -ge $((0x1500000)) ] \
    && ok "lowest load address $low lies behind the firmware's low-memory blocks (0x800000-0x1500000)" \
    || bad "lowest load address '$low' overlaps the OVMF S3 blocks"
low=$(readelf -lW "$TMPD/k-default.elf" 2>/dev/null | awk '$1=="LOAD" {print $3}' | sort | head -1)
[ "$low" = 0x0000000000100000 ] && ok "default base unchanged (1 MiB)" || bad "default base moved: '$low'"

n=0
for m in one:s3 two:s3zwei dead:s3kaputt; do
    mkimg "$TMPD/k-safe" "$TMPD/${m%%:*}.img" "${m#*:} nokbd nosched noproc nofs noring3" && n=$((n+1))
done
mkimg "$TMPD/k-safe" "$TMPD/sched.img" "s3 nokbd noproc nofs noring3" && n=$((n+1))
mkimg "$TMPD/k-safe" "$TMPD/gfx.img" "gfx s3 nokbd nosched noproc nofs noring3" && n=$((n+1))
mkimg "$TMPD/k-default" "$TMPD/old.img" "s3 nokbd nosched noproc nofs noring3" && n=$((n+1))
num "OVMF disks (Limine UEFI + kernel)" "$n" eq 6

echo "== 2. OVMF q35, one cycle: sleep, wake, everything back =="
L="$TMPD/l-one.txt"
run_cycles "$TMPD/one.img" "$L" 1 1
has "$L" "BdsDxe" "booted through OVMF (UEFI), not SeaBIOS"
has "$L" "s3: fadt=" "FADT, FACS and _S3 values found"
case $STATUS1 in *suspended*) ok "QEMU reports the machine as SLEEPING ($STATUS1)";; *) bad "state while sleeping: '$STATUS1'";; esac
has "$L" "s3: wach zyklus=1 woke=1 stufe=4" "OVMF resumed into the wake blob, which ran to stage 4 exactly once"
num "exit code" "$RC" eq 21
has "$L" "kernel: done" "the kernel runs on to its end after the wake-up"
num "APIC: lines saved" "$(val "$L" 's3: apic' leitungen)" ge 1
num "APIC: wrong afterwards" "$(val "$L" 's3: apic' danach-falsch)" eq 0
num "PCI: devices saved" "$(val "$L" 's3: pci' geraete)" ge 1
num "PCI: wrong afterwards" "$(val "$L" 's3: pci' danach-falsch)" eq 0
SV=$(val "$L" 's3: sci' vor); SN=$(val "$L" 's3: sci' nach)
if [ -n "$SV" ] && [ "$SV" = "$SN" ]; then ok "ACPI mode (SCI_EN) as before: $SN"; else bad "SCI_EN before=$SV after=$SN"; fi
num "RAM: pattern equal" "$(val "$L" 's3: speicher' gleich)" eq 1

echo "== 3. two cycles in a row ($OSUM_QEMU_ACCEL) =="
L="$TMPD/l-two.txt"
run_cycles "$TMPD/two.img" "$L" 2 1
case $STATUS2 in *suspended*) ok "the second sleep is real too ($STATUS2)";; *) bad "second sleep: '$STATUS2'";; esac
has "$L" "s3: wach zyklus=2 woke=1 stufe=4" "woke twice"
num "exit code" "$RC" eq 21

echo "== 4. scheduler and timer after the wake-up =="
L="$TMPD/l-sched.txt"
run_cycles "$TMPD/sched.img" "$L" 1 1
has "$L" "s3: wach zyklus=1 woke=1 stufe=4" "woke with the scheduler running"
num "timer ticks in 200 ms after the wake-up" "$(val "$L" 's3: ticks' ms)" ge 10
num "exit code" "$RC" eq 21

echo "== 5. several processors =="
for np in 2 4; do
    L="$TMPD/l-smp$np.txt"
    run_cycles "$TMPD/sched.img" "$L" 1 1 "$np"
    has "$L" "s3: wach zyklus=1 woke=1 stufe=4" "$np processors: woke"
    has "$L" "kernel: done" "$np processors: the kernel reaches its end"
done

echo "== 6. graphics mode comes back under OVMF =="
L="$TMPD/l-gfx.txt"
run_cycles "$TMPD/gfx.img" "$L" 1 1
has "$L" "s3: wach zyklus=1 woke=1 stufe=4" "gfx: woke"
DV=$(val "$L" 's3: bildmodus' dispi-vorher); DD=$(val "$L" 's3: bildmodus' danach)
[ "$DV" = "0x41" ] && ok "before the sleep: DISPI on ($DV)" || bad "DISPI before: '$DV'"
[ "$DD" = "0x41" ] && ok "after the restore: DISPI on again ($DD)" || bad "DISPI afterwards: '$DD'"

echo "== 7. OVMF i440fx (PIIX4 power management) =="
L="$TMPD/l-pc.txt"
run_cycles "$TMPD/one.img" "$L" 1 1 1 pc
case $STATUS1 in *suspended*) ok "i440fx: the machine sleeps ($STATUS1)";; *) bad "i440fx: state while sleeping: '$STATUS1'";; esac
has "$L" "s3: wach zyklus=1 woke=1 stufe=4" "i440fx: woke"

echo "== 8. counter-proof: poisoned wake blob must NOT come back =="
L="$TMPD/l-dead.txt"
run_cycles "$TMPD/dead.img" "$L" 1 0
case $STATUS1 in *suspended*) ok "it sleeps the same way ($STATUS1)";; *) bad "counter-proof did not sleep: '$STATUS1'";; esac
hasnot "$L" "s3: wach" "and does not come back -- the return path is this code and nothing else"
hasnot "$L" "kernel: done" "no end of the kernel"

echo "== 9. counter-proof: default base 1 MiB overlaps the firmware's blocks and cannot resume =="
L="$TMPD/l-old.txt"
run_cycles "$TMPD/old.img" "$L" 1 0
case $STATUS1 in *suspended*) ok "the default-base kernel sleeps ($STATUS1)";; *) bad "default-base kernel did not sleep: '$STATUS1'";; esac
hasnot "$L" "s3: wach" "default base: OVMF cannot resume (its PEI image in RAM is overwritten); this is why --base exists"

echo
echo "S3OVMF: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
