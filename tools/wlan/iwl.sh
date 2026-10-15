#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/iwl.sh -- gate for lib/wlan/iwl_probe.fi (W-AX201 milestone M1: identify, no writes).
#
# Host-only: QEMU has no Intel WLAN device, so there is nothing to boot. The test drives the REAL
# library against a simulated CSR block. With WLAN_AX201_FW=<iwlwifi-QuZ-a0-hr-b0-77.ucode> it also
# checks the SHA-256 pin and walks the real firmware TLVs, cross-checked by an independent Python
# walk (the blob is never checked into the repo, see docs/WLAN-AX201.md section 3).
#
# usage: bash tools/wlan/iwl.sh        exit 0 = all OK
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$PWD/lib"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== iwl M1: probe + firmware container =="
if $FIRNC tools/wlan/iwl.fi -o "$D/wiwl" 2> "$D/err"; then ok "tools/wlan/iwl.fi builds against lib/wlan/iwl_probe.fi"
else bad "tools/wlan/iwl.fi does not build"; head -20 "$D/err"; fi

if [ -x "$D/wiwl" ]; then
    if [ -n "${WLAN_AX201_FW:-}" ] && [ -f "$WLAN_AX201_FW" ]; then IN="$WLAN_AX201_FW"; else IN=/dev/null; fi
    "$D/wiwl" < "$IN" > "$D/out.txt"; rc=$?
    cat "$D/out.txt"
    [ $rc -eq 0 ] && ok "iwl test binary exit 0" || bad "iwl test binary exit $rc"
    p=$(grep -c '^  OK    ' "$D/out.txt" || true); f=$(grep -c '^  FAIL  ' "$D/out.txt" || true)
    [ "$f" -eq 0 ] && [ "$p" -ge 31 ] && ok "$p checks green" || bad "checks: $p ok / $f fail"
    if [ "$IN" != /dev/null ]; then
        py=$(python3 -I - "$IN" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
o, n = 80, 0
while o < len(d):
    t, l = struct.unpack('<II', d[o:o+8]); o += 8 + ((l + 3) & ~3); n += 1
print(n if o == len(d) else -1)
PY
)
        ft=$(sed -n 's/^TLVCOUNT //p' "$D/out.txt")
        [ -n "$ft" ] && [ "$ft" = "$py" ] && ok "TLV count Firn == Python ($ft)" || bad "TLV count Firn=$ft Python=$py"
    else
        echo "  (no WLAN_AX201_FW: real-blob checks F1-F4 skipped)"
    fi
    # negative control: a broken pin must fail the real-blob check
    if [ "$IN" != /dev/null ]; then
        mkdir -p "$D/lib"
        for e in lib/*; do [ "$(basename "$e")" = wlan ] || ln -s "$PWD/$e" "$D/lib/$(basename "$e")"; done
        cp -r lib/wlan "$D/lib/wlan"
        sed -i 's/0x39, 0xd7/0x38, 0xd7/' "$D/lib/wlan/iwl_probe.fi"
        FIRNLIB="$D/lib" $FIRNC tools/wlan/iwl.fi -o "$D/wneg" 2>/dev/null
        if [ -x "$D/wneg" ] && ! "$D/wneg" < "$IN" > /dev/null 2>&1; then ok "negative control: corrupted pin makes the gate fail"
        else echo "  (negative control not conclusive)"; fi
    fi
fi
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
