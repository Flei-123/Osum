#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
. tools/lib/summary.sh
summary_begin BOOTGZ
trap summary_guard EXIT
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
D=$(mktemp -d /root/abbilder/bootgz.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"; summary_guard' EXIT
osb_prepare "$D" || { echo "BOOTGZ: prepare failed"; exit 1; }
LOGIN="glogin: rect"
STICK="$D/stick.img"
SPEC="$STICK@@$OSB_OFF"
OLD=$(date -d '2026-01-02 03:04:06' +%s)
mcopy -i "$SPEC" ::osum.mb "$D/osum.mb" || { echo "BOOTGZ: kernel not on stick"; exit 1; }
python3 -I tools/bootgz/hang_kernel.py "$D/osum.mb" "$D/hang.mb" || exit 1
python3 -I tools/bootgz/hang_kernel.py "$D/osum.mb" "$D/hang-big.mb" 4096 || exit 1
gzip -9 -n -c "$D/hang.mb" > "$D/hang.gz"
gzip -9 -n -c "$D/hang-big.mb" > "$D/hang-big.gz"
gz_names() { mdir -b -i "$SPEC" :: 2>/dev/null | grep -ci 'osum.mb.gz'; }
boot_case() {
    local name=$1 label=$2 loader=${3:-$D/BOOTX64.EFI}
    mcopy -i "$SPEC" -o "$loader" ::EFI/BOOT/BOOTX64.EFI || return 1
    OSB_TAIL=3 osb_boot "$D" "$name" "$STICK" q35 ehci 60 "$LOGIN"
    T="$D/$name.txt"
}
expect_new() {
    grep -aq "$LOGIN" "$T" && ok "$1: login reached on the new kernel" || bad "$1: login not reached"
}

echo "== fresh gz is used =="
kernel_publish "$SPEC" "$D/osum.mb" 1
[ "$(gz_names)" = 1 ] && ok "kernel_publish writes osum.mb.gz" || bad "kernel_publish did not write the gz"
boot_case fresh "fresh gz"
grep -aq "osboot: gunzip /osum.mb" "$T" && ok "fresh gz: loader inflated /osum.mb" || bad "fresh gz: no gunzip line"
expect_new "fresh gz"

echo "== stale gz, same size, older than the kernel =="
kernel_publish "$SPEC" "$D/osum.mb" 0
touch -d @$OLD "$D/hang.gz"
mcopy -m -i "$SPEC" -o "$D/hang.gz" ::/osum.mb.gz
mcopy -i "$SPEC" -o "$D/osum.mb" ::/osum.mb
boot_case stale_time "stale gz (older)"
grep -aq "osboot: gunzip /osum.mb" "$T" && bad "stale gz (older): inflated anyway" || ok "stale gz (older): not inflated"
expect_new "stale gz (older)"

echo "== stale gz, different size, newer than the kernel =="
cp "$D/osum.mb" "$D/osum-old.mb"
touch -d @$OLD "$D/osum-old.mb"
mcopy -m -i "$SPEC" -o "$D/osum-old.mb" ::/osum.mb
mcopy -i "$SPEC" -o "$D/hang-big.gz" ::/osum.mb.gz
boot_case stale_size "stale gz (size)"
grep -aq "osboot: gunzip /osum.mb" "$T" && bad "stale gz (size): inflated anyway" || ok "stale gz (size): not inflated"
expect_new "stale gz (size)"

echo "== counter-proof: loader without the checks boots the stale kernel =="
mkdir -p "$D/nocheck/boot"
cp -r boot/common boot/uefi "$D/nocheck/boot/"
python3 -I - "$D/nocheck/boot/uefi/fsys.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("    if gz_older_than_raw(c, path, gp) {\n        return load(c, path, limit)\n    }\n", "")
s = s.replace("(on_disk == 0 || on_disk == raw_size)", "true")
open(p, "w").write(s)
PY
grep -q "gz_older_than_raw(c, path, gp)" "$D/nocheck/boot/uefi/fsys.fi" && bad "counter-proof patch did not apply" || ok "counter-proof loader built without the checks"
bash tools/bootloader/build.sh "$D/nocheck.efi" "$D/nocheck" > /dev/null 2>&1 || bad "counter-proof loader build failed"
mcopy -m -i "$SPEC" -o "$D/hang.gz" ::/osum.mb.gz
mcopy -i "$SPEC" -o "$D/osum.mb" ::/osum.mb
boot_case nocheck "counter-proof" "$D/nocheck.efi"
grep -aq "osboot: gunzip /osum.mb" "$T" && ok "counter-proof: stale gz inflated" || bad "counter-proof: stale gz not inflated"
grep -aq "$LOGIN" "$T" && bad "counter-proof: new kernel booted anyway" || ok "counter-proof: stale kernel hung, no login"

echo "== kernel_publish drops a stale gz =="
mcopy -i "$SPEC" -o "$D/hang.gz" ::/osum.mb.gz
kernel_publish "$SPEC" "$D/osum.mb" 0
[ "$(gz_names)" = 0 ] && ok "kernel_publish removed the stale gz" || bad "stale gz still on the stick"
boot_case dropped "dropped gz"
expect_new "dropped gz"

summary_emit "$pass" "$fail" 12
