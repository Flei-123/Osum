#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/s3dev/run.sh -- DD-12 / K-004c: THE DEVICES AFTER S3.
#
# After a real S3 a device has lost what it kept inside itself (rings, queues,
# slots, streams). kernel/pwr/s3dev.fi calls every driver's resume hook after
# the bus side is back. QEMU does not cut a device's power on its S3, so a plain
# sleep proves nothing: the word `s3loss` is the POWER-LOSS SIMULATION -- before
# the hooks run, every device is reset the way a power cut leaves it (NVMe
# controller disabled, AHCI HBA reset, xHCI host controller reset, e1000 reset,
# HD-Audio controller out of CRST). A resume hook that does not work leaves the
# device dead, and this runner sees it.
#
# One machine, two cores, with: an NVMe disk, an AHCI disk, a USB keyboard on an
# xHCI controller, an e1000 card behind QEMU's user network, an Intel HD-Audio
# controller. Three sleeps in a row (the kernel's `s3smp` entry, after the other
# cores run). Per cycle the runner checks:
#   * NVMe/AHCI: the first eight sectors read back with the SAME checksum as before
#     the sleep (`gleich=1`) -- after the controller was reset
#   * USB: the controller and the enumeration came back, the keyboard is there, and
#     a key typed through the QEMU monitor AFTER the wake-up arrives (`tasten>=1`)
#   * network: the card is up again and receives: an ARP request for the gateway is
#     answered (`rx>=1`)
#   * audio: the HD-Audio controller set up again
# Counter-check: the same run WITHOUT the resume hooks (`s3nohooks`): the devices
# stay dead -- the NVMe controller is not back, the keyboard types nothing, the
# card receives nothing. That is what shows that the checks above measure the
# hooks and not the emulator.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
TMPD=$(mktemp -d)
trap '[ -n "${S3DEV_KEEP:-}" ] && { rm -rf "$S3DEV_KEEP"; mkdir -p "$S3DEV_KEEP"; cp "$TMPD"/l-*.txt "$S3DEV_KEEP"/ 2>/dev/null; }; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: no number (expected $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, expected $op $want"; fi
}

for w in qemu-system-x86_64 sgdisk mkfs.vfat mcopy socat; do
    command -v "$w" >/dev/null 2>&1 || { echo "S3DEV: skipped, $w missing"; exit 0; }
done
[ -x "$LIMINE/limine" ] || { echo "S3DEV: skipped, Limine missing"; exit 0; }
CYCLES=${CYCLES:-3}
EXTRA=${S3DEV_EXTRA:-}

mkimg() { # kernel img cmdline
    local t="$TMPD/esp.img"
    printf 'timeout: 0\ndefault_entry: 1\n/s3\n    protocol: multiboot1\n    path: boot():/osum.mb\n    cmdline: %s\n' "$3" > "$TMPD/limine.conf"
    rm -f "$2" "$t"
    dd if=/dev/zero of="$2" bs=1M count=0 seek=48 status=none
    sgdisk --clear --new=1:2048:+40M --typecode=1:EF00 "$2" >/dev/null 2>&1 || return 1
    dd if=/dev/zero of="$t" bs=1M count=40 status=none
    mkfs.vfat -F 32 "$t" >/dev/null 2>&1 || return 1
    mcopy -i "$t" "$LIMINE/limine-bios.sys" ::/limine-bios.sys || return 1
    mcopy -i "$t" "$TMPD/limine.conf" ::/limine.conf || return 1
    mcopy -i "$t" "$1" ::/osum.mb || return 1
    dd if="$t" of="$2" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$t"
    "$LIMINE/limine" bios-install "$2" >/dev/null 2>&1
}

echo "== 1. build =="
bash tools/build-kernel.sh "$TMPD/k" > "$TMPD/b.txt" 2>&1 \
    && ok "kernel built ($(stat -c%s "$TMPD/k") bytes)" \
    || { bad "kernel build"; tail -8 "$TMPD/b.txt" | sed 's/^/        /'; echo "S3DEV: $pass OK, $fail FAIL"; exit 1; }
# `nvme` and `ahci` are two test words the kernel runs one at a time (hw.fi): two machines
WORDS="$EXTRA s3smp s3loss usb hidgen nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0 audio nokbd noproc nofs noring3"
mkimg "$TMPD/k" "$TMPD/a.img" "$WORDS nvme" && ok "boot disk (NVMe machine, hooks on)" || bad "boot disk"
mkimg "$TMPD/k" "$TMPD/b.img" "$WORDS ahci" && ok "boot disk (AHCI machine, hooks on)" || bad "boot disk (ahci)"
mkimg "$TMPD/k" "$TMPD/h.img" "$WORDS nvme s3nohooks" && ok "boot disk (counter-check: hooks off)" || bad "boot disk (nohooks)"
# two data disks with something on them (random, so a dead controller cannot read "the same" by luck)
dd if=/dev/urandom of="$TMPD/nvme.img" bs=1M count=8 status=none
dd if=/dev/urandom of="$TMPD/ahci.img" bs=1M count=8 status=none

# lauf name img cycles
lauf() {
    local name=$1 img=$2 cyc=$3
    local sock="$TMPD/mon.$1" L="$TMPD/l-$1.txt"
    rm -f "$L"; STATES=""
    cp "$TMPD/nvme.img" "$TMPD/nvme.$1"; cp "$TMPD/ahci.img" "$TMPD/ahci.$1"
    timeout 300 $QEMU_X86 -m 512 -smp 2 -drive "file=$img,format=raw,if=ide" \
        -drive "file=$TMPD/nvme.$1,format=raw,if=none,id=nv0" -device nvme,drive=nv0,serial=S3NVME \
        -device ahci,id=ahci0 -drive "file=$TMPD/ahci.$1,format=raw,if=none,id=ah0" -device ide-hd,bus=ahci0.0,drive=ah0 \
        -device qemu-xhci,id=x0 -device usb-kbd,bus=x0.0 \
        -netdev user,id=n0 -device e1000,netdev=n0 \
        -audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0 \
        -serial "file:$L" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! c i st n
    for c in $(seq 1 "$cyc"); do
        for i in $(seq 1 900); do
            n=$(grep -ac 's3: schlafe' "$L" 2>/dev/null)
            [ "${n:-0}" -ge "$c" ] && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        sleep 1
        st=$(echo 'info status' | socat - "UNIX-CONNECT:$sock" 2>/dev/null | tr -d '\r' | grep -ao 'VM status: .*' | head -1)
        STATES="$STATES|$st"
        case $st in *suspended*) ;; *) break ;; esac
        echo system_wakeup | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
        # the kernel waits for a key after the USB resume: type it as soon as the line is there
        for i in $(seq 1 300); do
            n=$(grep -ac 's3: dev usb' "$L" 2>/dev/null)
            [ "${n:-0}" -ge "$c" ] && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        sleep 0.4
        echo 'sendkey a' | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
        for i in $(seq 1 300); do
            n=$(grep -ac 's3: smp zyklus=' "$L" 2>/dev/null)
            [ "${n:-0}" -ge "$c" ] && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
    done
    for i in $(seq 1 150); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; RC=$?
}
cnt() { grep -ac "$2" "$1" 2>/dev/null; }
keys_ok() { tr -d '\r' < "$1" | grep -a 's3: usb tasten=' | sed 's/.*tasten=//' | awk '$1>=1{n++} END{print n+0}'; }
rx_ok() { tr -d '\r' < "$1" | grep -a 's3: net arp rx=' | sed 's/.*rx=\([0-9]*\).*/\1/' | awk '$1>=1{n++} END{print n+0}'; }

echo "== 2. three sleeps with the devices reset before the hooks run (NVMe machine) =="
lauf dev "$TMPD/a.img" "$CYCLES"
L="$TMPD/l-dev.txt"
num "the VM really slept" "$(echo "$STATES" | tr '|' '\n' | grep -ac suspended)" eq "$CYCLES"
num "devices were reset (power-loss simulation)" "$(cnt "$L" 's3: geraete verloren')" eq "$CYCLES"
num "NVMe: resume ok" "$(cnt "$L" 's3: dev nvme da=1 resume=1')" eq "$CYCLES"
num "NVMe: the first sectors read back with the same checksum" "$(cnt "$L" 's3: dev nvme da=1 resume=1 gleich=1')" eq "$CYCLES"
num "USB: controller and enumeration came back, keyboard present" "$(cnt "$L" 's3: dev usb da=1 resume=1 .*kbd=1')" eq "$CYCLES"
num "USB: a key typed after the wake-up arrived" "$(keys_ok "$L")" eq "$CYCLES"
num "network: the card came back, link up" "$(cnt "$L" 's3: dev net da=1 resume=1 link=1')" eq "$CYCLES"
num "network: it receives again (ARP reply from the gateway)" "$(rx_ok "$L")" eq "$CYCLES"
num "audio: the controller and the codec graph are set up again" "$(cnt "$L" 's3: dev hda da=1 resume=1')" eq "$CYCLES"
num "every sleep returned rc=0" "$(cnt "$L" 's3: smp zyklus=[0-9] rc=0')" eq "$CYCLES"
num "return code of the machine (isa-debug-exit)" "$RC" eq 21

if [ -n "${S3DEV_ONLY1:-}" ]; then echo "S3DEV: $pass OK, $fail FAIL (only machine 1)"; exit 0; fi
echo "== 2b. the same with the AHCI controller instead of NVMe =="
lauf deva "$TMPD/b.img" "$CYCLES"
L="$TMPD/l-deva.txt"
num "the VM really slept" "$(echo "$STATES" | tr '|' '\n' | grep -ac suspended)" eq "$CYCLES"
num "AHCI: resume ok" "$(cnt "$L" 's3: dev ahci da=1 resume=1')" eq "$CYCLES"
num "AHCI: the first sectors read back with the same checksum" "$(cnt "$L" 's3: dev ahci da=1 resume=1 gleich=1')" eq "$CYCLES"
num "every sleep returned rc=0" "$(cnt "$L" 's3: smp zyklus=[0-9] rc=0')" eq "$CYCLES"

echo "== 3. counter-check s3nohooks: the same reset, no resume hooks =="
lauf nohooks "$TMPD/h.img" 1
L="$TMPD/l-nohooks.txt"
num "slept" "$(echo "$STATES" | tr '|' '\n' | grep -ac suspended)" ge 1
num "devices were reset" "$(cnt "$L" 's3: geraete verloren')" ge 1
num "NVMe: without the hook the controller is NOT back (resume=0)" "$(cnt "$L" 's3: dev nvme da=1 resume=0')" ge 1
num "USB: without the hook the key does not arrive" "$(keys_ok "$L")" eq 0
num "network: without the hook nothing is received" "$(rx_ok "$L")" eq 0

echo
echo "S3DEV: $pass OK, $fail FAIL"
[ "$fail" = 0 ]
