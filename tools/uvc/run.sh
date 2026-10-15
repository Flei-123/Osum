#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/uvc/run.sh -- gate for the USB Video Class PROTOCOL half (r809).
#
# MEASURES: lib/uvc/uvc.fi parses a UVC configuration descriptor (YUY2 +
# MJPEG formats, frames, isoc alternate settings with the high-bandwidth
# multiplier, bulk streaming), picks frame + endpoint setting, encodes the
# 26 byte probe/commit block and validates the device answer, assembles
# frames from payload packets (FID toggle, EOF, ERR, overflow, bad header
# length), checks JPEG markers and converts YUY2 to XRGB. 3000 corrupted
# descriptors and 5000 random packets must never exceed the capacities.
# Negative controls: the oracle goes red when a check is removed.
#
# DOES NOT MEASURE: any USB traffic. There is no camera driver and no QEMU
# test device (QEMU 7.2 has no usb-camera, QEMU >= 10 has). The checks at
# the end keep both claims from rotting.
#
# Usage: bash tools/uvc/run.sh
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

printf 'import uvc.uvc\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "lib compiles with --profile=kernel" \
    || { bad "lib does not compile with --profile=kernel"; head -5 "$T/k.err"; }
"$FIRNC" tools/uvc/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds" || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    timeout 60 "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0 (no panic)" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 60 ] && ok "oracle: $nok promises OK (>= 60)" || bad "oracle: only $nok OK (< 60)"
    pass=$((pass+nok))
fi

mutate() { # name sed-expression
    local name=$1 expr=$2
    local L="$T/lib-$name"
    mkdir -p "$L/uvc"
    for d in lib/*; do
        [ "$(basename "$d")" = uvc ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    sed -e "$expr" lib/uvc/uvc.fi > "$L/uvc/uvc.fi"
    if cmp -s lib/uvc/uvc.fi "$L/uvc/uvc.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/uvc/oracle.fi -o "$T/o-$name" 2>/dev/null; then
        bad "control $name: mutated oracle does not build"
        return
    fi
    local out nf rc
    out=$(timeout 20 "$T/o-$name" 2>&1)
    rc=$?
    nf=$(printf '%s\n' "$out" | grep -c '^FAIL')
    if [ "$nf" -gt 0 ] || [ "$rc" != 0 ]; then
        ok "control $name: oracle goes red (FAIL=$nf rc=$rc)"
    else
        bad "control $name: oracle stays green on a broken lib"
    fi
}
mutate desc_bounds   's/if len < 2 || at + len > total {/if false {/'
mutate hdr_len       's/if hle < 2 || hle > 12 || hle > n {/if false {/'
mutate overflow      's/if cg(st, S_LEN) + k > cg(st, S_CAP) {/if false {/'
mutate fid_drop      's/fid != cg(st, S_FID) \&\& cg(st, S_LEN) > 0/false/'
mutate err_bit       's/^        cs(st, S_BAD, 1)$/        cs(st, S_BAD, 0)/'
mutate probe_frame   's/if ld8(p, 3) != frame { return false }//'
mutate probe_payload 's/if mp == 0 || mp > 0x10000 { return false }//'
mutate multiplier    's/\* (1 + ((wmax >> 11) \& 3))/* 1/'
mutate jpeg_eoi      's/if ld8(p, n - 2) != 0xFF || ld8(p, n - 1) != 0xD9 { return false }//'
mutate clamp         's/if v < 0 { return 0 }//'
mutate bulk_first    's/if alt_type(r, i) == 2 {/if false {/'
mutate frame_cap     's/if n < MAX_FRAME {/if n < 1000 {/'

# test-bed facts
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    if qemu-system-x86_64 -device help 2>&1 | grep -q 'name "usb-camera"'; then
        bad "QEMU has usb-camera now: write the end-to-end gate (xHCI isoc + driver) and update this check"
    else
        ok "QEMU has no usb-camera (protocol half only; end-to-end gate needs QEMU >= 10 or hardware)"
    fi
fi
# no kernel code may claim a camera driver before there is a gate
if grep -rqiE 'uvc\.(parse_config|asm_feed|build_probe)' kernel --include=*.fi; then
    bad "kernel uses lib/uvc now: add an end-to-end gate and update this check"
else
    ok "kernel has no UVC driver yet (protocol half only)"
fi

echo "uvc: $pass promises, $fail errors"
[ "$fail" = 0 ]
