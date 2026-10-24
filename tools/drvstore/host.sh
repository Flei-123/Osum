#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
MK="python3 -I tools/drvstore/mkpkg.py"
printf 'OSUMMOD-dummy' > "$D/dummy.omod"

$MK build "$D/s" --name edudemo --rank 10 --module "$D/dummy.omod" --rights pci-cfg \
    --match "pci 1234:11e8" --match "pciclass 0c03:30" --match "usb 8087:0a2b" --match "acpi ALP0016" \
    --match "pci 8086:24fd:8086:9010" >/dev/null && ok "build valid package" || bad "build valid package"
[ "$($MK check "$D/s/edudemo")" = OK ] && ok "check valid package" || bad "check valid package"

$MK build "$D/s" --name badsig --module "$D/dummy.omod" --match "pci 1234:11e8" --bad-sig >/dev/null
($MK check "$D/s/badsig" || true) | grep -q "signature invalid" && ok "counter-proof: flipped signature rejected" || bad "flipped signature accepted"

$MK build "$D/s" --name tamper --module "$D/dummy.omod" --match "pci 1234:11e8" --tamper >/dev/null
($MK check "$D/s/tamper" || true) | grep -q "signature invalid" && ok "counter-proof: tampered manifest rejected" || bad "tampered manifest accepted"

$MK build "$D/s" --name garbage --module "$D/dummy.omod" --match "pci 1234:11e8" --garbage >/dev/null
($MK check "$D/s/garbage" || true) | grep -q "no key=value" && ok "counter-proof: broken manifest rejected" || bad "broken manifest accepted"

$MK build "$D/s" --name nomod --module "$D/dummy.omod" --match "pci 1234:11e8" --no-module >/dev/null
($MK check "$D/s/nomod" || true) | grep -q "module file dummy.omod missing" && ok "counter-proof: missing module file" || bad "missing module accepted"

$MK build "$D/s" --name badid --module "$D/dummy.omod" --match "pci 12345:11e8" >/dev/null 2>&1 \
    && bad "bad match id accepted" || ok "counter-proof: bad match id refused at build"
$MK build "$D/s" --name BadName --module "$D/dummy.omod" --match "pci 1234:11e8" >/dev/null 2>&1 \
    && bad "bad name accepted" || ok "counter-proof: bad name refused at build"

echo "DRVSTORE-HOST: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
