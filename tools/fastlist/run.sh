#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../lib/brand-env.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../lib/summary.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
summary_begin FASTLIST
trap summary_guard EXIT
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
[ -f "$OSB_CODE" ] && [ -f "$OSB_VARS" ] || { echo "FASTLIST: OVMF firmware missing"; exit 1; }
D=$(mktemp -d /root/abbilder/fastlistgate.XXXXXX)
trap 'rm -rf "$D"; summary_guard' EXIT
osb_prepare "$D" || { echo "FASTLIST: prepare failed"; exit 1; }
LOGIN="glogin: rect"

variant() {
    local name=$1 from=$2 to=$3
    cp "$D/stick.img" "$D/$name.base"
    sed "s/ $from / $to /g" "$D/limine.conf" > "$D/$name.conf"
    python3 tools/bootloader/mkcfg.py "$D/$name.conf" "$D/$name.cfg" --timeout 0 --logo /osboot.logo > /dev/null
    mcopy -i "$D/$name.base@@$OSB_OFF" -o "$D/$name.conf" ::limine.conf
    mcopy -i "$D/$name.base@@$OSB_OFF" -o "$D/$name.cfg" ::osboot.cfg
}

grep -q " fastboot " "$D/limine.conf" && ok "default entry carries the fastboot word" || bad "default entry has no fastboot word"

echo "== fastboot: /bin listing skipped =="
osb_boot "$D" fast "$D/stick.img" q35 ehci 90 "$LOGIN"
t="$D/fast.txt"
grep -aq "$LOGIN" "$t" && ok "fast: login reached (${OSB_MS} ms)" || bad "fast: login not reached"
grep -aq "osum: bin" "$t" && bad "fast: /bin listing still printed" || ok "fast: /bin listing skipped"
grep -aq "EXCEPTION\|panic:" "$t" && bad "fast: fault line" || ok "fast: no fault line"
abw=$(grep -a -m1 "^acpi: pmhz=" "$t" | sed 's/.*abw=//' | tr -dc '0-9')
[ -n "$abw" ] && [ "$abw" -le 10 ] && ok "fast: short PM-timer cross-check within 1% (abw=$abw)" || bad "fast: PM-timer cross-check off or missing (abw=${abw:-none})"
grep -aq "ticks: NO TIMER IRQ\|time: no tsc" "$t" && bad "fast: clock fallback line" || ok "fast: clock adopted without fallback"

echo "== counter-proof: same stick without the word =="
variant slow fastboot slowboot
osb_boot "$D" slow "$D/slow.base" q35 ehci 90 "$LOGIN"
t="$D/slow.txt"
grep -aq "$LOGIN" "$t" && ok "slow: login reached (${OSB_MS} ms)" || bad "slow: login not reached"
grep -aq "^osum: bin .:2" "$t" && ok "slow: /bin listing printed" || bad "slow: /bin listing missing"

echo "== counter-proof: near-miss word fastbootx =="
variant near fastboot fastbootx
osb_boot "$D" near "$D/near.base" q35 ehci 90 "$LOGIN"
grep -aq "^osum: bin .:2" "$D/near.txt" && ok "near: fastbootx keeps the listing" || bad "near: fastbootx disabled the listing"

summary_emit "$pass" "$fail" 9
