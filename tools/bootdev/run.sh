#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../lib/summary.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
summary_begin BOOTDEV
trap summary_guard EXIT
BASE_REF=${BASE_REF:-5ce1209f2}
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
[ -f "$OSB_CODE" ] && [ -f "$OSB_VARS" ] || { echo "BOOTDEV: OVMF firmware missing"; exit 1; }
D=$(mktemp -d /root/abbilder/bootdevgate.XXXXXX)
trap 'rm -rf "$D"; summary_guard' EXIT
osb_prepare "$D" || { echo "BOOTDEV: prepare failed"; exit 1; }
LOGIN="glogin: rect"

first_try() { grep -a "versuch " "$1" | head -1 | sed 's/.*versuch //'; }
tries() { grep -ac "versuch " "$1"; }

usb_case() {
    local name=$1 bus=$2 label=$3
    osb_boot "$D" "$name" "$D/stick.img" q35 "$bus" 90 "$LOGIN"
    local t="$D/$name.txt"
    [ "$(first_try "$t")" = "usb" ] && ok "$label: first root candidate is usb" || bad "$label: first candidate is '$(first_try "$t")'"
    grep -aq "rootsel: usb -- WURZEL" "$t" && ok "$label: root mounted from usb" || bad "$label: usb root missing"
    [ "$(tries "$t")" = 1 ] && ok "$label: one candidate tried" || bad "$label: $(tries "$t") candidates tried"
    grep -aq "versuch ahci" "$t" && bad "$label: ahci probed" || ok "$label: ahci not probed"
    grep -aq "$LOGIN" "$t" && ok "$label: login reached (${OSB_MS} ms)" || bad "$label: login not reached"
}

echo "== bootdev: EHCI stick =="
usb_case ehci ehci "ehci"
echo "== bootdev: xHCI stick =="
usb_case xhci xhci "xhci"

echo "== counter-proof: bogus bootdev value keeps the old order =="
sed 's/^cmdline /cmdline bootdev=bogus /' "$D/osboot.cfg" > "$D/bogus.cfg"
grep -q "bootdev=bogus" "$D/bogus.cfg" || bad "bogus: cfg edit failed"
osb_with_cfg "$D" bogus "$D/bogus.cfg"
osb_boot "$D" bogus "$D/bogus.base" q35 ehci 90 "$LOGIN"
rm -f "$D/bogus.base"
t="$D/bogus.txt"
[ "$(first_try "$t")" != "usb" ] && ok "bogus value: usb not first ('$(first_try "$t")')" || bad "bogus value: usb still first"
grep -aq "rootsel: usb -- WURZEL" "$t" && ok "bogus value: root still found via usb" || bad "bogus value: root lost"
grep -aq "$LOGIN" "$t" && ok "bogus value: login reached (${OSB_MS} ms)" || bad "bogus value: no login"

echo "== counter-proof: old osboot (no bootdev word) =="
mkdir "$D/base"
git archive "$BASE_REF" boot lib tools/bootloader/build.sh | tar -x -C "$D/base"
ln -s "$PWD/vendor" "$D/base/vendor"
(cd "$D/base" && bash tools/bootloader/build.sh "$D/OLD.EFI" > "$D/old-build.txt" 2>&1) || { tail -3 "$D/old-build.txt"; bad "old osboot build failed"; }
rm -rf "$D/base"
cp "$D/stick.img" "$D/old.base"
mcopy -i "$D/old.base@@$OSB_OFF" -o "$D/OLD.EFI" ::EFI/BOOT/BOOTX64.EFI
osb_boot "$D" old "$D/old.base" q35 ehci 90 "$LOGIN"
rm -f "$D/old.base"
t="$D/old.txt"
[ "$(first_try "$t")" != "usb" ] && ok "old osboot: usb not first ('$(first_try "$t")')" || bad "old osboot: usb first without the word"
[ "$(tries "$t")" -gt 1 ] && ok "old osboot: $(tries "$t") candidates tried" || bad "old osboot: only one candidate"
grep -aq "$LOGIN" "$t" && ok "old osboot: login reached (${OSB_MS} ms)" || bad "old osboot: no login"

echo "== bootdev on other buses still boots =="
for spec in "ide pc ide" "nvme q35 nvme"; do
    set -- $spec
    osb_boot "$D" "b$1" "$D/stick.img" "$2" "$3" 90 "$LOGIN"
    grep -aq "$LOGIN" "$D/b$1.txt" && ok "$1: login reached" || bad "$1: login not reached"
    grep -aq "EXCEPTION\|panic:" "$D/b$1.txt" && bad "$1: fault line" || ok "$1: no fault"
done

summary_emit "$pass" "$fail" 18
