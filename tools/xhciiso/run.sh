#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/xhciiso/run.sh -- gate for the xHCI isochronous ARITHMETIC (r813, host only).
#
# MEASURES: lib/xhciiso/iso.fi -- endpoint context words (type, CErr = 0, interval,
# Mult, Max Burst, Max ESIT), wMaxPacketSize split, TBC/TLBPC, Isoch TRB words,
# completion-code classes. Golden values, plus negative controls (the oracle goes
# red when a rule in the lib is broken).
# The end-to-end part (QEMU xHCI + usb-audio, isoc OUT) is tools/xhciisoq/run.sh.
#
# Usage: bash tools/xhciiso/run.sh
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

printf 'import xhciiso.iso\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "lib compiles with --profile=kernel" \
    || { bad "lib does not compile with --profile=kernel"; head -5 "$T/k.err"; }
"$FIRNC" tools/xhciiso/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
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
    mkdir -p "$L/xhciiso"
    for d in lib/*; do
        [ "$(basename "$d")" = xhciiso ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    sed -e "$expr" lib/xhciiso/iso.fi > "$L/xhciiso/iso.fi"
    if cmp -s lib/xhciiso/iso.fi "$L/xhciiso/iso.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/xhciiso/oracle.fi -o "$T/o-$name" 2>/dev/null; then
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

mutate type_out      's/EPT_ISOC_OUT: u64 = 1/EPT_ISOC_OUT: u64 = 2/'
mutate type_in       's/EPT_ISOC_IN: u64 = 5/EPT_ISOC_IN: u64 = 6/'
mutate mps_mask      's/return raw \& 0x7FF/return raw/'
mutate burst_hs      's/return (raw >> 11) \& 3/return 0/'
mutate burst_clamp   's/if ss_burst > 15 {/if ss_burst > 99 {/'
mutate mult_clamp    's/if m > 2 {/if m > 9 {/'
mutate esit_mult     's/return mps \* (burst + 1) \* (mult + 1)/return mps * (burst + 1)/'
mutate ivl_fs_shift  's/var v: u64 = n - 1 + 3/var v: u64 = n - 1/'
mutate ivl_clamp     's/if v > 15 {/if v > 99 {/'
mutate dw0_esit_hi   's/(((esit >> 16) \& 0xFF) << 24)/0/'
mutate dw1_cerr      's/return (art << 3) | (burst << 8) | (mps << 16)/return (3 << 1) | (art << 3) | (burst << 8) | (mps << 16)/'
mutate dw4_esit      's/((esit \& 0xFFFF) << 16)/((esit \& 0xFF) << 16)/'
mutate pk_roundup    's/return (len + mps - 1) \/ mps/return len \/ mps/'
mutate pk_zero       's/if len == 0 {/if len == 99999 {/'
mutate fit_17bit     's/ || len > 0x1FFFF//'
mutate fit_esit      's/return len <= max_esit(mps, burst, mult)/return true/'
mutate tbc_ss_only   's/if speed < 4 || npk == 0 {/if npk == 0 {/'
mutate tbc_round     's/return (npk + burst) \/ (burst + 1) - 1/return npk \/ (burst + 1) - 1/'
mutate tlbpc_hs      's/return npk - 1$/return 0/'
mutate tlbpc_zero    's/        return burst$/        return 0/'
mutate st_mask       's/(len \& 0x1FFFF) | (t << 17)/len | (t << 17)/'
mutate st_clamp      's/if t > 31 {/if t > 99 {/'
mutate ctl_type      's/TRB_ISOCH: u64 = 5/TRB_ISOCH: u64 = 1/'
mutate ctl_sia       's/c = c | (1 << 31)/c = c | (1 << 30)/'
mutate ctl_ioc       's/c = c | (1 << 5)/c = c | (1 << 6)/'
mutate ctl_isp       's/c = c | (1 << 2)/c = c | (1 << 3)/'
mutate cc_short      's/if code == 1 || code == 13 {/if code == 1 {/'
mutate cc_under      's/if code == 14 || code == 15 {/if code == 14 {/'
mutate cc_missed     's/if code == 23 {/if code == 24 {/'

echo "XHCIISO: $pass ok, $fail fail"
[ "$fail" = 0 ]
