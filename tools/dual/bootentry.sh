#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
. tools/dual/lib-cli.sh

BAU=${1:?usage: bootentry.sh <imagedir> [old-imagedir] [outdir]}
OLD=${2:-}
if [ -n "${3:-}" ]; then
    OUT=$3
    mkdir -p "$OUT"
else
    OUT=$(mktemp -d)
    trap 'rm -rf "$OUT"' EXIT
fi
LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}

ok=0; bad=0
pass() { printf '  [ ok ] %s\n' "$*"; ok=$((ok+1)); }
fail() { printf '  [FAIL] %s\n' "$*"; bad=$((bad+1)); }
title() { printf '\n=== %s\n' "$*"; }
check() { local what=$1; shift; if "$@"; then pass "$what"; else fail "$what"; fi }

[ -f "$BAU/osum.mb" ] && [ -f "$BAU/root.img" ] || { echo "== $BAU lacks osum.mb or root.img" >&2; exit 1; }
[ -f "$LIMINE/BOOTX64.EFI" ] || { echo "== $LIMINE/BOOTX64.EFI missing" >&2; exit 1; }

DISK_MIB=480
ESP_MIB=100
MSR_MIB=16
NTFS_MIB=150
REC_MIB=50

part_range() {
    local img=$1 n=$2 first last
    first=$(sgdisk -i "$n" "$img" 2>/dev/null | sed -n 's/First sector: \([0-9]*\).*/\1/p')
    last=$(sgdisk -i "$n" "$img" 2>/dev/null | sed -n 's/Last sector: \([0-9]*\).*/\1/p')
    echo "$first $((last - first + 1))"
}

part_sum() {
    local img=$1 n=$2 first count
    read -r first count < <(part_range "$img" "$n")
    dd if="$img" bs=512 skip="$first" count="$count" status=none | sha256sum | cut -d' ' -f1
}

foreign_sums() {
    local img=$1 n
    for n in 2 3 4; do part_sum "$img" "$n"; done
}

esp_offset() {
    local first count
    read -r first count < <(part_range "$1" 1)
    echo $((first * 512))
}

esp_get() {
    mcopy -n -i "$1@@$(esp_offset "$1")" "::$2" "$3" 2>/dev/null
}

esp_has() {
    mdir -i "$1@@$(esp_offset "$1")" "::$2" > /dev/null 2>&1
}

make_disk() {
    local img=$1 with_fallback=$2
    local esp_start=2048 esp_sectors=$((ESP_MIB * 2048))
    local msr_start=$((esp_start + esp_sectors)) msr_sectors=$((MSR_MIB * 2048))
    local ntfs_start=$((msr_start + msr_sectors)) ntfs_sectors=$((NTFS_MIB * 2048))
    local rec_start=$((ntfs_start + ntfs_sectors)) rec_sectors=$((REC_MIB * 2048))
    rm -f "$img"
    dd if=/dev/zero of="$img" bs=1M count=0 seek="$DISK_MIB" status=none
    sgdisk -o "$img" > /dev/null 2>&1
    sgdisk -n "1:$esp_start:$((esp_start + esp_sectors - 1))" -t 1:EF00 -c 1:"EFI system partition" "$img" > /dev/null 2>&1
    sgdisk -n "2:$msr_start:$((msr_start + msr_sectors - 1))" -t 2:0C01 -c 2:"Microsoft reserved partition" "$img" > /dev/null 2>&1
    sgdisk -n "3:$ntfs_start:$((ntfs_start + ntfs_sectors - 1))" -t 3:0700 -c 3:"Basic data partition" "$img" > /dev/null 2>&1
    sgdisk -n "4:$rec_start:$((rec_start + rec_sectors - 1))" -t 4:2700 -c 4:"Windows recovery" "$img" > /dev/null 2>&1
    local esp=$OUT/esp.tmp
    dd if=/dev/zero of="$esp" bs=1M count="$ESP_MIB" status=none
    mkfs.vfat -F 32 -n SYSTEM "$esp" > /dev/null 2>&1
    mmd -i "$esp" ::/EFI ::/EFI/Microsoft ::/EFI/Microsoft/Boot
    mcopy -i "$esp" tools/dual/beweis.efi ::/EFI/Microsoft/Boot/bootmgfw.efi
    printf 'foreign boot configuration data\n' > "$OUT/bcd.tmp"
    mcopy -i "$esp" "$OUT/bcd.tmp" ::/EFI/Microsoft/Boot/BCD
    if [ "$with_fallback" = 1 ]; then
        mmd -i "$esp" ::/EFI/BOOT
        yes 'WINDOWS FALLBACK LOADER' | head -c 90000 > "$OUT/fallback.orig"
        mcopy -i "$esp" "$OUT/fallback.orig" ::/EFI/BOOT/BOOTX64.EFI
    fi
    dd if="$esp" of="$img" bs=512 seek="$esp_start" conv=notrunc status=none
    rm -f "$esp" "$OUT/bcd.tmp"
    printf 'NTFS    foreign data' | dd of="$img" bs=512 seek="$ntfs_start" conv=notrunc status=none
    printf 'foreign recovery' | dd of="$img" bs=512 seek="$rec_start" conv=notrunc status=none
}

serial_text() {
    tr -d '\000' < "$1" 2>/dev/null
}

install_into() {
    local img=$1 ser=$2 base=$3
    local saved=$BAU
    BAU=$base
    lauf "$img" "dualcli /dev/hdb --quelle /dev/hda --ja --name hdb" "$ser"
    BAU=$saved
}

assert_common() {
    local img=$1 ser=$2 before=$3
    local slug=$MARKE_KURZ product=$MARKE_PRODUKT
    local text conf
    text=$(serial_text "$ser")
    conf=$OUT/limine.out
    check "installer reports done" grep -q 'dual: done' <<< "$text"
    check "menu has two entries" grep -q 'dual: menu=2' <<< "$text"
    check "readback verification passed" grep -q 'boot: verified' <<< "$text"
    check "no boot error" bash -c '! grep -q "boot-error" <<< "$1"' _ "$text"
    check "log names the exact ESP path \\EFI\\$slug\\BOOTX64.EFI" grep -qF "installer: boot file \\EFI\\$slug\\BOOTX64.EFI" <<< "$text"
    check "log names the stick menu entry" grep -qF "installer: register entry Register $product in firmware boot menu" <<< "$text"
    esp_get "$img" "/EFI/$slug/BOOTX64.EFI" "$OUT/slug-loader.out"
    check "Limine at \\EFI\\$slug\\BOOTX64.EFI equals the shipped loader" cmp -s "$OUT/slug-loader.out" "$LIMINE/BOOTX64.EFI"
    esp_get "$img" "/EFI/$slug/osum.mb" "$OUT/kernel.out"
    check "kernel at \\EFI\\$slug\\osum.mb equals the image kernel" cmp -s "$OUT/kernel.out" "$BAU/osum.mb"
    esp_get "$img" /limine.conf "$conf"
    check "limine.conf has the product entry" grep -qF "/$product" "$conf"
    check "limine.conf points at the slug kernel" grep -qF "boot():/EFI/$slug/osum.mb" "$conf"
    check "limine.conf chainloads the Windows boot manager" grep -qF "boot():/EFI/Microsoft/Boot/bootmgfw.efi" "$conf"
    esp_get "$img" /EFI/Microsoft/Boot/bootmgfw.efi "$OUT/bm.out"
    check "bootmgfw.efi unchanged" cmp -s "$OUT/bm.out" tools/dual/beweis.efi
    esp_get "$img" /EFI/Microsoft/Boot/BCD "$OUT/bcd.out"
    check "BCD unchanged" grep -q 'foreign boot configuration data' "$OUT/bcd.out"
    check "foreign partitions (MSR, data, recovery) byte-identical" test "$(foreign_sums "$img")" = "$before"
    check "sgdisk finds no problems" bash -c 'sgdisk -v "$1" 2>&1 | grep -q "No problems found"' _ "$img"
}

title "A. existing \\EFI\\BOOT\\BOOTX64.EFI must survive"
make_disk "$OUT/a.img" 1
BEFORE_A=$(foreign_sums "$OUT/a.img")
install_into "$OUT/a.img" "$OUT/ser-a.txt" "$BAU"
assert_common "$OUT/a.img" "$OUT/ser-a.txt" "$BEFORE_A"
esp_get "$OUT/a.img" /EFI/BOOT/BOOTX64.EFI "$OUT/fallback.out"
check "existing \\EFI\\BOOT\\BOOTX64.EFI byte-identical" cmp -s "$OUT/fallback.out" "$OUT/fallback.orig"

title "B. no \\EFI\\BOOT\\BOOTX64.EFI -> it is created"
make_disk "$OUT/b.img" 0
BEFORE_B=$(foreign_sums "$OUT/b.img")
check "precondition: no fallback loader" bash -c '! mdir -i "$1@@$2" ::/EFI/BOOT > /dev/null 2>&1' _ "$OUT/b.img" "$(esp_offset "$OUT/b.img")"
install_into "$OUT/b.img" "$OUT/ser-b.txt" "$BAU"
assert_common "$OUT/b.img" "$OUT/ser-b.txt" "$BEFORE_B"
esp_get "$OUT/b.img" /EFI/BOOT/BOOTX64.EFI "$OUT/created.out"
check "\\EFI\\BOOT\\BOOTX64.EFI created and equals Limine" cmp -s "$OUT/created.out" "$LIMINE/BOOTX64.EFI"

title "C. dialog texts"
for lang in en de; do
    for key in dual.boot.title dual.boot.a dual.boot.b dual.boot.c dual.boot.d dual.boot.title2; do
        check "locale/$lang has $key" grep -q "^$key = " "locale/$lang/messages"
    done
done
check "dialog text is built from the brand path, not hardcoded" grep -q 'bootcfg.loader_display()' kernel/user/bootnote.fi

if [ -n "$OLD" ]; then
    title "D. counter-proof: old build overwrites \\EFI\\BOOT\\BOOTX64.EFI"
    make_disk "$OUT/c.img" 1
    install_into "$OUT/c.img" "$OUT/ser-c.txt" "$OLD"
    esp_get "$OUT/c.img" /EFI/BOOT/BOOTX64.EFI "$OUT/fallback-old.out"
    check "old build clobbered the existing fallback loader (gate detects it)" bash -c '! cmp -s "$1" "$2"' _ "$OUT/fallback-old.out" "$OUT/fallback.orig"
fi

printf '\nbootentry: %d ok, %d fail\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
