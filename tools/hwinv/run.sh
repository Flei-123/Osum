#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hwinv/run.sh -- host gate for lib/hwinv (hardware inventory classifier) + 4 mutations.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
$FIRNC tools/hwinv/check.fi -o "$T/c" 2> "$T/c.err" && ok "check builds" || { bad "build"; head -5 "$T/c.err"; echo "HWINV: $pass passed, $fail failed"; exit 1; }
"$T/c" > "$T/c.txt" 2>&1
n1=$(grep -c '^OK' "$T/c.txt"); n2=$(grep -c '^FAIL' "$T/c.txt")
sed -n 's/^FAIL /  FAIL  check: /p' "$T/c.txt"
[ "$n2" = 0 ] && [ "$n1" -ge 35 ] && ok "classifier: $n1 checks OK, 0 FAIL" || bad "classifier ($n1 ok, $n2 fail)"
pass=$((pass+n1))
mut() {
    rm -rf "$T/lib-mut"; mkdir -p "$T/lib-mut"
    for d in lib/*; do [ "$(basename "$d")" = hwinv ] || ln -sfn "$ROOT/$d" "$T/lib-mut/$(basename "$d")"; done
    mkdir -p "$T/lib-mut/hwinv"
    for f in lib/hwinv/*.fi; do cp "$f" "$T/lib-mut/hwinv/"; done
    sed -i "$3" "$T/lib-mut/hwinv/$2"
    cmp -s "lib/hwinv/$2" "$T/lib-mut/hwinv/$2" && { bad "mutation $1 did not change the lib"; return; }
    if FIRNLIB="$T/lib-mut" $FIRNC tools/hwinv/check.fi -o "$T/m" 2>/dev/null; then
        local m; m=$("$T/m" 2>&1 | grep -c '^FAIL')
        [ "$m" -gt 0 ] && ok "mutation ($1) -> $m red checks" || bad "mutation $1 stayed green"
    else bad "mutation $1 build failed"; fi
}
mut "raid class not recognised" scan.fi 's/cls == 0x0104/cls == 0x0105/'
mut "nvme class not recognised" scan.fi 's/cls == 0x0108/cls == 0x0109/'
mut "serial io i2c range shifted" scan.fi 's/dev >= 0x9d60 \&\& dev <= 0x9d65/dev >= 0x9e60 \&\& dev <= 0x9e65/'
mut "uefi never reported" scan.fi 's/bump(FW_UEFI)/bump(FW_SEEN)/'
mut "i2c-hid id not recognised" scan.fi 's/"PNP0C50\\0"/"PNP0C51\\0"/'
mut "ns flag never set" scan.fi 's/bump(ACPI_NS)/bump(ACPI_SEEN)/'
echo "HWINV: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
