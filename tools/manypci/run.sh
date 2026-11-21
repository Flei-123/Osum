#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../lib/summary.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
summary_begin MANYPCI
trap summary_guard EXIT
: "${STICK_IMG:?STICK_IMG is required}"
: "${KERNEL:?KERNEL is required}"
: "${BASE_KERNEL:?BASE_KERNEL is required}"
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
[ -f "$OSB_CODE" ] && [ -f "$OSB_VARS" ] || { echo "MANYPCI: OVMF firmware missing"; exit 1; }
D=$(mktemp -d /root/abbilder/manypcigate.XXXXXX)
trap 'rm -rf "$D"; summary_guard' EXIT
osb_prepare "$D" || { echo "MANYPCI: prepare failed"; exit 1; }
cp "$D/stick.img" "$D/new.img"
cp "$D/stick.img" "$D/old.img"
kernel_publish "$D/old.img@@$OSB_OFF" "$BASE_KERNEL" || { echo "MANYPCI: base kernel publish failed"; exit 1; }
LOGIN="glogin: rect"

run_case() {
    local name=$1 img=$2 bus=$3 want=$4
    osb_boot "$D" "$name" "$img" q35 "$bus" 120 "$LOGIN"
    local t="$D/$name.txt"
    if [ "$want" = good ]; then
        grep -aq "rootsel: usb -- WURZEL" "$t" && ok "$name: root mounted from usb" || bad "$name: usb root missing"
        grep -aq "$LOGIN" "$t" && ok "$name: login reached (${OSB_MS} ms)" || bad "$name: login not reached"
        grep -aq "device table full" "$t" && bad "$name: pci table overflowed" || ok "$name: pci table did not overflow"
    else
        grep -aq "rootsel: usb -- WURZEL" "$t" && bad "$name: old kernel found the root" || ok "$name: old kernel loses the root"
        grep -aq "no device carries a root" "$t" && ok "$name: old kernel stops at rootsel" || bad "$name: old kernel did not stop at rootsel"
    fi
}

echo "== second xHCI carries the stick, first one is empty =="
run_case twohc_new "$D/new.img" twohc good
run_case twohc_old "$D/old.img" twohc bad

echo "== more than 32 PCI functions, stick behind the last root port =="
run_case many_new "$D/new.img" manypci good
run_case many_old "$D/old.img" manypci bad

echo "== no usable root device: the failure line names the counts =="
osb_boot "$D" noroot "$D/new.img" q35 scsi 90 "no device carries a root"
t="$D/noroot.txt"
grep -aq "no device carries a root" "$t" && ok "noroot: kernel stops at rootsel" || bad "noroot: kernel did not stop at rootsel"
grep -aq "rootsel: pci functions=[0-9]* xhci=[0-9]*" "$t" && ok "noroot: pci and xhci counts reported" || bad "noroot: counts line missing"

summary_emit "$pass" "$fail" 12
