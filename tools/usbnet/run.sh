#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbnet/run.sh -- gate for the USB-tethering PROTOCOL half (L-015).
#
# MEASURES: lib/usbnet/rndis.fi encodes the RNDIS control messages byte for
# byte (golden layout), validates every device reply (length, status, info
# buffer inside the message, data offset not inside the header, runt
# frames), wraps/unwraps Ethernet frames, parses the CDC-ECM MAC string.
# Negative controls: the oracle goes red when a bounds check is removed.
#
# DOES NOT MEASURE: any USB traffic -- that is tools/usbnet/qemu.sh (CDC-ECM
# driver, kernel/drv/net/usbnet.fi). RNDIS is still protocol-only; the check
# at the end keeps that claim from rotting.
#
# Usage: bash tools/usbnet/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
export FIRNLIB="$ROOT/lib"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

printf 'import usbnet.rndis\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "lib compiles with --profile=kernel" \
    || { bad "lib does not compile with --profile=kernel"; head -5 "$T/k.err"; }
"$FIRNC" tools/usbnet/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds" || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0 (no panic)" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 35 ] && ok "oracle: $nok promises OK (>= 35)" || bad "oracle: only $nok OK (< 35)"
    pass=$((pass+nok))
fi

mutate() { # name sed-expression
    local name=$1 expr=$2
    local L="$T/lib-$name"
    mkdir -p "$L/usbnet"
    for d in lib/*; do
        [ "$(basename "$d")" = usbnet ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    sed -e "$expr" lib/usbnet/rndis.fi > "$L/usbnet/rndis.fi"
    if cmp -s lib/usbnet/rndis.fi "$L/usbnet/rndis.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/usbnet/oracle.fi -o "$T/o-$name" 2>/dev/null; then
        bad "control $name: mutated oracle does not build"
        return
    fi
    local out nf rc
    out=$("$T/o-$name" 2>&1)
    rc=$?
    nf=$(printf '%s\n' "$out" | grep -c '^FAIL')
    if [ "$nf" -gt 0 ] || [ "$rc" != 0 ]; then
        ok "control $name: oracle goes red (FAIL=$nf rc=$rc)"
    else
        bad "control $name: oracle stays green on a broken lib"
    fi
}
mutate packet_bounds 's/if off + dl > l { return false }//'
mutate info_bounds   's/if io + 8 + il > l { return false }/if false { return false }/'
mutate runt          's/if dl < 14 || dl > 9216 { return false }//'
mutate hdr_offset    's/if off < PACKET_HDR_LEN { return false }//'
mutate offset_trap   's/put32(dst, 8, PACKET_HDR_LEN - 8)/put32(dst, 8, PACKET_HDR_LEN)/'
mutate status        's/return le32(p, 12) == STATUS_SUCCESS/return true/'
mutate mac_ascii     's/hi_hi != 0 || lo_hi != 0/false/'

# test-bed facts
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    qemu-system-x86_64 -device help 2>&1 | grep -q 'name "usb-net"' \
        && ok "QEMU has usb-net (RNDIS + CDC for the later end-to-end test)" \
        || bad "QEMU has no usb-net"
fi
if [ -f kernel/drv/net/usbnet.fi ] && grep -q 'DRV_ECM' kernel/usb/usb.fi \
    && grep -q 'KIND_USBNET' kernel/net/netdev.fi; then
    ok "kernel has the CDC-ECM driver (end-to-end gate: tools/usbnet/qemu.sh)"
else
    bad "kernel CDC-ECM driver is missing (kernel/drv/net/usbnet.fi, DRV_ECM, KIND_USBNET)"
fi
# RNDIS driver (r811): the kernel binds RNDIS (DRV_RNDIS) and the end-to-end gate exists
if [ -f tools/usbrndis/run.sh ] && grep -q 'DRV_RNDIS' kernel/usb/usb.fi \
    && grep -q 'attach_rndis' kernel/drv/net/usbnet.fi; then
    ok "kernel has the RNDIS driver (end-to-end gate: tools/usbrndis/run.sh)"
else
    bad "kernel RNDIS driver or its gate is missing (DRV_RNDIS, attach_rndis, tools/usbrndis/run.sh)"
fi

echo "usbnet: $pass promises, $fail errors"
[ "$fail" = 0 ]
