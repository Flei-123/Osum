#!/bin/bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
set -u
cd "$(dirname "$0")/../.."
. tools/bootloader/lib.sh
pass=0; fail=0
ok()  { echo "  OK    $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
D=$(mktemp -d /root/abbilder/osbiosgate.XXXXXX)
[ -n "${KEEP:-}" ] || trap 'rm -rf "$D"' EXIT
bios_prepare "$D" || { echo "OSBOOT-BIOS: prepare failed"; exit 1; }
LOGIN="glogin: rect"

login_case() {
    local name=$1 mach=$2 bus=$3 label=$4
    echo "== $label =="
    bios_boot "$D" "$name" "$D/stick.img" "$mach" "$bus" 120 "$LOGIN"
    local t="$D/$name.txt"
    grep -aq "osboot (bios)" "$t" && ok "$label: BIOS loader banner" || bad "$label: no BIOS loader banner"
    grep -aq "osboot: start " "$t" && ok "$label: osboot started the kernel" || bad "$label: no 'osboot: start' line"
    grep -aq "EXCEPTION\|kernel halted\|panic:" "$t" && bad "$label: fault: $(grep -a 'EXCEPTION\|kernel halted\|panic:' "$t" | head -1)" || ok "$label: no fault line"
    grep -aq "^smp: cpus=[0-9]*  acpi=1" "$t" && ok "$label: ACPI found" || bad "$label: smp: acpi=1 missing"
    grep -aq "osum: mount=1" "$t" && ok "$label: root mounted from module" || bad "$label: osum: mount=1 missing"
    grep -aq "mb: flags=0x[0-9a-f]*1[0-9a-f]\{3\}" "$t" && ok "$label: multiboot info has framebuffer flag" || bad "$label: framebuffer flag missing"
    grep -aq "$LOGIN" "$t" && ok "$label: login screen reached (${OSB_MS} ms)" || bad "$label: login screen not reached"
    grep -aq "boot menu" "$t" && bad "$label: menu shown without a key" || ok "$label: no menu without a key"
}

error_case() {
    local name=$1 cfg=$2 want=$3 label=$4
    echo "== counter-proof: $label =="
    bios_with_cfg "$D" "$name" "$cfg"
    OSB_TAIL=2 bios_boot "$D" "$name" "$D/$name.base" q35 ide 40 "$want"
    rm -f "$D/$name.base"
    local t="$D/$name.txt"
    grep -aq "$want" "$t" && ok "$label: message '$want'" || bad "$label: message '$want' missing"
    grep -aq "^smp: cpus\|osum: " "$t" && bad "$label: kernel started anyway" || ok "$label: kernel not started"
}

login_case bq35 q35 ide "SeaBIOS q35 + AHCI disk"
login_case bpc pc ide "SeaBIOS i440fx + IDE disk"
login_case busb q35 usb "SeaBIOS q35 + USB stick"

python3 tools/bootloader/mkcfg.py "$D/limine.conf" "$D/single.cfg" --timeout 0 --entries 1 > /dev/null
sed '2a bogus value' "$D/single.cfg" > "$D/broken.cfg"
error_case cbroken "$D/broken.cfg" "config is broken, line 3" "broken config"
sed 's#^kernel .*#kernel /missing.mb#' "$D/single.cfg" > "$D/nokern.cfg"
error_case cnokern "$D/nokern.cfg" "kernel not found: /missing.mb" "missing kernel"
error_case cnocfg - "config not found: /osboot.cfg" "missing config"

echo "== menu shown: Enter boots the default =="
python3 tools/bootloader/mkcfg.py "$D/limine.conf" "$D/menu.cfg" --timeout 0 --menu shown > /dev/null
bios_with_cfg "$D" cmenu "$D/menu.cfg"
bios_start "$D" cmenu "$D/cmenu.base" q35 ide
if osb_wait_text "$D" cmenu "boot menu" 60; then
    ok "menu: shown"
    osb_hmp "$D" cmenu "sendkey ret" 0.5
    osb_wait_text "$D" cmenu "$LOGIN" 120 && ok "menu: Enter boots to login" || bad "menu: no login after Enter"
else
    bad "menu: not shown"
fi
bios_finish "$D" cmenu
rm -f "$D/cmenu.base"

echo "== forced menu: Esc during the key window =="
python3 tools/bootloader/mkcfg.py "$D/limine.conf" "$D/key.cfg" --timeout 0 --keywait 8000 > /dev/null
bios_with_cfg "$D" ckey "$D/key.cfg"
bios_start "$D" ckey "$D/ckey.base" q35 ide
if osb_wait_text "$D" ckey "osboot (bios)" 60; then
    osb_hmp "$D" ckey "sendkey esc" 0.3
    osb_wait_text "$D" ckey "boot menu" 30 && ok "Esc opens the menu" || bad "Esc did not open the menu"
else
    bad "key window: no banner"
fi
bios_finish "$D" ckey
rm -f "$D/ckey.base"

echo "== $pass ok, $fail fail =="
[ "$fail" -eq 0 ]
