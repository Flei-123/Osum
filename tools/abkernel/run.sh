#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/abkernel/run.sh -- boot-try counter of osboot (UEFI): a trial kernel in slot 2 that
# hangs or resets before it can report anything falls back to slot 1 without a human.
#
#   bash tools/abkernel/run.sh
#
# SECTIONS
#   1. normal boot (default_entry 1): slot 1, no counter file written
#   2. healthy trial: confirmed after every boot -> slot 2 each time
#   3. trial kernel hangs: two tries on slot 2, third boot slot 1, fallback sticks
#   4. trial kernel resets (triple fault): same
#   5. re-arm resets the counter and tries slot 2 again
#   6. counter-proof: old osboot without counter boots the hanging slot 2 forever
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d /tmp/abkernel-run.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
. tools/bootloader/lib.sh

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: '$2', expected '$3'"; fi; }

KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
BOOT_SECS=${BOOT_SECS:-40}

make_conf() {
    local file=$1 default=$2
    {
        echo "timeout: 0"
        echo "default_entry: $default"
        echo
        echo "/Slot A"
        echo "    protocol: multiboot1"
        echo "    path: boot():/osum-a.mb"
        echo "    cmdline: osum"
        echo
        echo "/Slot B"
        echo "    protocol: multiboot1"
        echo "    path: boot():/osum-b.mb"
        echo "    cmdline: osum"
    } > "$file"
}

make_disk() {
    local disk=$1 efi=$2 bmode=$3 default=$4
    rm -f "$disk"
    head -c 64M /dev/zero > "$disk"
    sgdisk -n 1:2048:+60M -t 1:EF00 "$disk" > /dev/null
    mkfs.vfat -F 32 --offset 2048 "$disk" > /dev/null
    local esp="$disk@@$OSB_OFF"
    mmd -i "$esp" ::EFI ::EFI/BOOT
    mcopy -i "$esp" "$efi" ::EFI/BOOT/BOOTX64.EFI
    bash tools/abkernel/stub.sh "$OUT/a.mb" STUB-SLOT-A up
    bash tools/abkernel/stub.sh "$OUT/b.mb" "STUB-SLOT-B-$bmode" "$bmode"
    mcopy -i "$esp" "$OUT/a.mb" ::osum-a.mb
    mcopy -i "$esp" "$OUT/b.mb" ::osum-b.mb
    make_conf "$OUT/limine.conf" "$default"
    mcopy -i "$esp" "$OUT/limine.conf" ::limine.conf
}

power_cycle() {
    local disk=$1 name=$2
    cp "$OSB_VARS" "$OUT/$name.vars"
    rm -f "$OUT/$name.txt"
    timeout $((BOOT_SECS + 10)) qemu-system-x86_64 "${KVM[@]}" -machine q35 -m 512 -smp 1 \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OSB_CODE" \
        -drive "if=pflash,format=raw,unit=1,file=$OUT/$name.vars" \
        -drive "file=$disk,format=raw,if=none,id=d" -device ide-hd,drive=d,bus=ide.0,bootindex=0 \
        -serial "file:$OUT/$name.txt" -display none -no-reboot -pidfile "$OUT/$name.pid" &
    local i=0
    while [ $i -lt $((BOOT_SECS * 5)) ]; do
        grep -aq "STUB-SLOT-" "$OUT/$name.txt" 2>/dev/null && break
        sleep 0.2
        i=$((i+1))
    done
    sleep 0.5
    kill "$(cat "$OUT/$name.pid" 2>/dev/null)" 2>/dev/null
    wait 2>/dev/null
    rm -f "$OUT/$name.vars"
}

slot_of() {
    if grep -aq "STUB-SLOT-A" "$1" 2>/dev/null; then echo A
    elif grep -aq "STUB-SLOT-B" "$1" 2>/dev/null; then echo B
    else echo none; fi
}

counter() { mcopy -i "$1@@$OSB_OFF" ::osboot.try - 2>/dev/null | tr -d '\n' || true; }
counter_set() { printf '%s\n' "$2" > "$OUT/try"; mcopy -o -i "$1@@$OSB_OFF" "$OUT/try" ::osboot.try; }

cycles() {
    local disk=$1 tag=$2 n=$3 seq=""
    local i
    for i in $(seq 1 "$n"); do
        power_cycle "$disk" "$tag$i"
        seq="$seq$(slot_of "$OUT/$tag$i.txt")"
    done
    echo "$seq"
}

echo "== 0. build =="
bash tools/bootloader/build.sh "$OUT/new.efi" > "$OUT/build.txt" 2>&1 && ok "osboot with counter built" || { tail -5 "$OUT/build.txt"; bad "osboot build"; }
mkdir -p "$OUT/nocount" && cp -r boot "$OUT/nocount/boot" && sed -i "/trycount.guard/d" "$OUT/nocount/boot/uefi/main.fi"
bash tools/bootloader/build.sh "$OUT/old.efi" "$OUT/nocount" > "$OUT/build-old.txt" 2>&1
if [ -f "$OUT/old.efi" ] && ! cmp -s "$OUT/old.efi" "$OUT/new.efi"; then ok "osboot without the counter call built"; else bad "osboot without the counter call"; fi

echo
echo "== 1. normal boot, default_entry 1 =="
D="$OUT/d1.img"
make_disk "$D" "$OUT/new.efi" hang 1
eq "boots slot A" "$(cycles "$D" n 1)" "A"
eq "no counter file" "$(counter "$D")" ""

echo
echo "== 2. healthy trial, confirmed after every boot =="
D="$OUT/d2.img"
make_disk "$D" "$OUT/new.efi" up 2
seq=""
for k in 1 2 3; do
    power_cycle "$D" "h$k"
    seq="$seq$(slot_of "$OUT/h$k.txt")"
    counter_set "$D" 0
done
eq "slot per boot" "$seq" "BBB"

echo
echo "== 3. trial kernel hangs =="
D="$OUT/d3.img"
make_disk "$D" "$OUT/new.efi" hang 2
eq "boots 1..5" "$(cycles "$D" g 5)" "BBAAA"
eq "counter stays at limit" "$(counter "$D")" "2"
grep -aq "falling back to slot 1" "$OUT/g3.txt" && ok "loader says why" || bad "no fallback message"

echo
echo "== 4. trial kernel resets (triple fault) =="
D="$OUT/d4.img"
make_disk "$D" "$OUT/new.efi" reset 2
eq "boots 1..4" "$(cycles "$D" r 4)" "BBAA"

echo
echo "== 5. re-arm after fallback =="
counter_set "$D" 0
eq "boots after re-arm" "$(cycles "$D" q 3)" "BBA"

echo
echo "== 6. counter-proof: old osboot =="
D="$OUT/d6.img"
make_disk "$D" "$OUT/old.efi" hang 2
eq "boots 1..4" "$(cycles "$D" o 4)" "BBBB"

echo
echo "RESULT: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
