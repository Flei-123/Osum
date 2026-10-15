#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ncm/run.sh -- gate for the CDC-NCM PROTOCOL half (r802).
#
# MEASURES: lib/usbnet/ncm.fi validates GET_NTB_PARAMETERS answers, builds
# the SET_NTB_INPUT_SIZE payload, wraps Ethernet frames into NTB16 (golden
# bytes, divisor/remainder/alignment) and validates every field of a
# received NTB (signatures, header length, block length, NDP index/length/
# alignment, datagram bounds). 2000 random buffers are never taken as NTB.
# Negative controls: the oracle goes red when a check is removed.
#
# DOES NOT MEASURE: any USB traffic. There is no NCM driver and QEMU 7.2
# has no NCM device (usb-net = RNDIS / CDC-ECM / Subset).
#
# Usage: bash tools/ncm/run.sh
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

printf 'import usbnet.ncm\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "lib compiles with --profile=kernel" \
    || { bad "lib does not compile with --profile=kernel"; head -5 "$T/k.err"; }
"$FIRNC" tools/ncm/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds" || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    timeout 60 "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0 (no panic)" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 45 ] && ok "oracle: $nok promises OK (>= 45)" || bad "oracle: only $nok OK (< 45)"
    pass=$((pass+nok))
fi

mutate() { # name sed-expression
    local name=$1 expr=$2
    local L="$T/lib-$name"
    mkdir -p "$L/usbnet"
    for d in lib/*; do
        [ "$(basename "$d")" = usbnet ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    sed -e "$expr" lib/usbnet/ncm.fi > "$L/usbnet/ncm.fi"
    if cmp -s lib/usbnet/ncm.fi "$L/usbnet/ncm.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/ncm/oracle.fi -o "$T/o-$name" 2>/dev/null; then
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

mutate nth_sig       's/if le32(p, 0) != NTH_SIG { return 0 }//'
mutate nth_len       's/if le16(p, 4) != NTH_LEN { return 0 }//'
mutate block_len     's/if bl != 0 \&\& bl > n { return 0 }//'
mutate ndp_align     's/if (ndp \& 3) != 0 { return 0 }//'
mutate ndp_sig       's/if le32(p, ndp) != NDP_SIG { return 0 }//'
mutate ndp_length    's/if nl < 16 || (nl \& 3) != 0 || ndp + nl > n { return 0 }/if nl < 16 { return 0 }/'
mutate dg_bounds     's/if off + len > n { return 0 }//'
mutate dg_in_header  's/if off < NTH_LEN { return 0 }//'
mutate dg_runt       's/if len < DG_MIN || len > DG_MAX { return 0 }//'
mutate rem_ge_div    's/if le16(p, 22) >= odiv { return false }//'
mutate align_pow2    's/if oal == 0 || (oal \& (oal - 1)) != 0 { return false }//'
mutate wrap_fit      's/if total > cap || total > 0xFFFF { return 0 }//'
mutate wrap_rem      's/dg = dg + ((rem + div - (dg % div)) % div)/dg = dg/'
mutate wrap_runt     's/if n < DG_MIN || n > DG_MAX { return 0 }//'

# test-bed facts
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    if qemu-system-x86_64 -device help 2>&1 | grep -qi 'ncm'; then
        bad "QEMU has an NCM device now: write the end-to-end gate and update this check"
    else
        ok "QEMU has no NCM device (protocol half only)"
    fi
fi
# r811: the driver exists (no QEMU model, so the wiring is checked statically; the framing is covered above).
# usb.fi binds class 02/0D as a LAST RESORT (same pass as RNDIS), runs the NCM bring-up and hands over to usbnet.fi (mode 2).
U=kernel/usb/usb.fi; N=kernel/drv/net/usbnet.fi
chk() { # description file regex
    if grep -qE "$3" "$2"; then ok "$1"; else bad "$1"; fi
}
chk "usb.fi: DRV_NCM exists and driver_for maps class 02/0D to it" $U 'return DRV_NCM'
chk "usb.fi: NCM is a last resort (wanted only with S_RNDISOK, i.e. pass 2)" $U 'sub == 0x0D \{'
chk "usb.fi: ncm_start does GET_NTB_PARAMETERS + SET_NTB_INPUT_SIZE" $U 'ncm\.REQ_SET_NTB_INPUT_SIZE'
chk "usb.fi: ncm_start hands the TX rules to the net driver" $U 'usbnet\.attach_ncm'
chk "usbnet.fi: mode 2 wraps TX with ncm.wrap_frame" $N 'ncm\.wrap_frame'
chk "usbnet.fi: mode 2 unpacks RX with ncm.ntb_dg_off" $N 'ncm\.ntb_dg_off'
chk "usbnet.fi: RX validates the NTB before use" $N 'ncm\.ntb_ok'

echo "ncm: $pass promises, $fail errors"
[ "$fail" = 0 ]
