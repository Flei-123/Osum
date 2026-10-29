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
    grep -aq "Boot entries" "$t" && bad "$label: menu shown without a key" || ok "$label: no menu without a key"
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

python3 tools/bootloader/mkcfg.py "$D/limine.conf" "$D/single.cfg" --timeout 0 --entries 1 > /dev/null
sed '2a bogus value' "$D/single.cfg" > "$D/broken.cfg"
error_case cbroken "$D/broken.cfg" "config is broken, line 3" "broken config"
sed 's#^kernel .*#kernel /missing.mb#' "$D/single.cfg" > "$D/nokern.cfg"
error_case cnokern "$D/nokern.cfg" "kernel not found: /missing.mb" "missing kernel"

echo "== counter-proof: no osboot.cfg and no limine.conf =="
cp "$D/stick.img" "$D/cnocfg.base"
mdel -i "$D/cnocfg.base@@$OSB_OFF" ::osboot.cfg
osb_without_limine "$D" cnocfg
OSB_TAIL=8 osb_boot "$D" cnocfg "$D/cnocfg.base" q35 ehci 40 "config not found: /osboot.cfg"
rm -f "$D/cnocfg.base"
grep -aq "config not found: /osboot.cfg" "$D/cnocfg.txt" && ok "no config: message" || bad "no config: message missing"
grep -aq "returning to firmware" "$D/cnocfg.txt" && ok "no config: returns to firmware" || bad "no config: no return to firmware"

echo "== osboot.cfg missing: entries come from limine.conf =="
osb_with_cfg "$D" nocfg -
osb_boot "$D" nocfg "$D/nocfg.base" q35 ehci 90 "$LOGIN"
rm -f "$D/nocfg.base"
grep -aq "osboot: start " "$D/nocfg.txt" && ok "limine.conf fallback: osboot started the kernel" || bad "limine.conf fallback: kernel not started"
grep -aq "$LOGIN" "$D/nocfg.txt" && ok "limine.conf fallback: login screen reached" || bad "limine.conf fallback: login screen not reached"

echo "== failed default entry: menu with countdown, next entry boots =="
python3 tools/bootloader/mkcfg.py "$D/limine.conf" "$D/two.cfg" --timeout 0 --entries 2 --logo /osboot.logo > /dev/null
sed '0,/^kernel .*/s##kernel /missing.mb#' "$D/two.cfg" > "$D/fb.cfg"
osb_with_cfg "$D" fb "$D/fb.cfg"
osb_boot "$D" fb "$D/fb.base" q35 ehci 120 "$LOGIN"
rm -f "$D/fb.base"
grep -aq "kernel not found: /missing.mb" "$D/fb.txt" && ok "fallback: error reported" || bad "fallback: error missing"
grep -aq "Boot entries" "$D/fb.txt" && ok "fallback: menu shown after the failure" || bad "fallback: no menu"
grep -aq "$LOGIN" "$D/fb.txt" && ok "fallback: second entry reached login" || bad "fallback: login not reached"

echo "== splash: logo pixels, spinner, no menu =="
python3 tools/bootloader/mkcfg.py "$D/limine.conf" "$D/hold.cfg" --timeout 0 --keywait 12000 --logo /osboot.logo > /dev/null
osb_with_cfg "$D" hold "$D/hold.cfg"
osb_start "$D" hold "$D/hold.base" q35 ehci
if osb_wait_text "$D" hold "osboot" 60; then
    sleep 4
    osb_shot "$D" hold shotA
    sleep 1
    osb_shot "$D" hold shotB
    python3 -I tools/bootloader/shotcheck.py logo "$D/shotA.ppm" "$D/osboot.logo" && ok "splash: logo pixels centered and exact" || bad "splash: logo pixels do not match"
    python3 -I tools/bootloader/shotcheck.py spinner "$D/shotA.ppm" "$D/osboot.logo" "$D/shotB.ppm" && ok "splash: spinner drawn and animated" || bad "splash: spinner missing or frozen"
    grep -aq "Boot entries" "$D/hold.txt" && bad "splash: menu visible without key" || ok "splash: no menu without key"
else
    bad "splash: osboot did not start"
fi
osb_stop "$D" hold

echo "== Esc opens the menu, Enter boots =="
osb_start "$D" esc "$D/hold.base" q35 ehci
if osb_wait_text "$D" esc "osboot" 60; then
    sleep 4
    osb_hmp "$D" esc "sendkey esc" 0.5
    osb_wait_text "$D" esc "Boot entries" 20 && ok "Esc: menu shown" || bad "Esc: no menu"
    sleep 1
    osb_shot "$D" esc shotM
    python3 -I tools/bootloader/shotcheck.py nologo "$D/shotM.ppm" "$D/osboot.logo" && ok "Esc: logo replaced by the menu" || bad "Esc: logo still on screen"
    osb_hmp "$D" esc "sendkey ret" 0.5
    osb_wait_text "$D" esc "$LOGIN" 90 && ok "Esc: Enter boots to login" || bad "Esc: login not reached after Enter"
else
    bad "Esc: osboot did not start"
fi
osb_stop "$D" esc

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
