#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
[ -f "$OSB_CODE" ] && [ -f "$OSB_VARS" ] || { echo "OSBOOT: OVMF firmware missing"; exit 1; }
D=$(mktemp -d /root/abbilder/osbootgate.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
osb_prepare "$D" || { echo "OSBOOT: prepare failed"; exit 1; }
LOGIN="glogin: rect"

login_case() {
    local name=$1 mach=$2 bus=$3 label=$4
    echo "== $label =="
    osb_boot "$D" "$name" "$D/stick.img" "$mach" "$bus" 90 "$LOGIN"
    local t="$D/$name.txt"
    grep -aq "osboot: start " "$t" && ok "$label: osboot started the kernel" || bad "$label: no 'osboot: start' line"
    grep -aq "EXCEPTION\|kernel halted\|panic:" "$t" && bad "$label: fault: $(grep -a 'EXCEPTION\|kernel halted\|panic:' "$t" | head -1)" || ok "$label: no fault line"
    grep -aq "^smp: cpus=[0-9]*  acpi=1" "$t" && ok "$label: ACPI found via copied RSDP" || bad "$label: smp: acpi=1 missing"
    grep -aq "osum: mount=1" "$t" && ok "$label: root mounted from module" || bad "$label: osum: mount=1 missing"
    grep -aq "$LOGIN" "$t" && ok "$label: login screen reached (${OSB_MS} ms)" || bad "$label: login screen not reached"
}

error_case() {
    local name=$1 cfg=$2 want=$3 label=$4
    echo "== counter-proof: $label =="
    osb_with_cfg "$D" "$name" "$cfg"
    OSB_TAIL=8 osb_boot "$D" "$name" "$D/$name.base" q35 ehci 40 "$want"
    rm -f "$D/$name.base"
    local t="$D/$name.txt"
    grep -aq "$want" "$t" && ok "$label: message '$want'" || bad "$label: message '$want' missing"
    grep -aq "returning to firmware" "$t" && ok "$label: returns to firmware" || bad "$label: no return to firmware"
    grep -aq "^smp: cpus\|osum: " "$t" && bad "$label: kernel started anyway" || ok "$label: kernel not started"
}

login_case eq35 q35 ehci "OVMF q35 + EHCI stick"
login_case eide pc ide "OVMF i440fx + IDE disk"
login_case envme q35 nvme "OVMF q35 + NVMe disk"

sed '2a bogus value' "$D/osboot.cfg" > "$D/broken.cfg"
error_case cbroken "$D/broken.cfg" "config is broken, line 3" "broken config"
sed 's#^kernel .*#kernel /missing.mb#' "$D/osboot.cfg" > "$D/nokern.cfg"
error_case cnokern "$D/nokern.cfg" "kernel not found: /missing.mb" "missing kernel"
error_case cnocfg - "config not found: /osboot.cfg" "missing config"

echo "== default beyond entry count falls back to entry 1 =="
sed 's/^default .*/default 9/' "$D/osboot.cfg" > "$D/fall.cfg"
osb_with_cfg "$D" fall "$D/fall.cfg"
osb_boot "$D" fall "$D/fall.base" q35 ehci 60 "^smp: cpus"
rm -f "$D/fall.base"
first=$(grep -m1 '^entry ' "$D/osboot.cfg" | cut -d' ' -f2-)
grep -aq "osboot: start $first" "$D/fall.txt" && ok "default 9: started entry 1 ($first)" || bad "default 9: entry 1 not started"
grep -aq "^smp: cpus" "$D/fall.txt" && ok "default 9: kernel runs" || bad "default 9: kernel did not run"

echo "== control: Limine stick unchanged =="
osb_boot "$D" lim "$D/limine.img" q35 ehci 90 "$LOGIN"
grep -aq "$LOGIN" "$D/lim.txt" && ok "Limine: login screen reached (${OSB_MS} ms)" || bad "Limine: login screen not reached"
grep -aq "osboot" "$D/lim.txt" && bad "Limine control printed osboot lines" || ok "Limine control: no osboot line"

echo "OSBOOT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
