#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ssam/run.sh -- host gate for lib/ssam (Surface Aggregator serial hub protocol).
#
# MEASURES: CRC, frame encoding, framing parser with resync, ACK/NAK, request/response
# matching, retries, event queue, HID-over-SAM descriptor handling. Golden bytes come from
# the independent Python reference tools/ssam/ref.py. Fuzz: 200000 random bytes.
# Negative controls: the oracle goes red when a check in the library is removed.
#
# DOES NOT MEASURE: the UART, the kernel driver or the real embedded controller.
#
# Usage: bash tools/ssam/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

farm() { # dir
    local L=$1
    mkdir -p "$L"
    for d in lib/*; do
        [ "$(basename "$d")" = ssam ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    mkdir -p "$L/ssam" "$L/ssamgold"
    PYTHONPATH=tools/ssam python3 -B tools/ssam/gengold.py > "$L/ssamgold/golden.fi"
}

L0="$T/lib0"
farm "$L0"
for f in lib/ssam/*.fi; do ln -s "$ROOT/$f" "$L0/ssam/$(basename "$f")"; done

printf 'import ssam.ssamlink\nimport ssam.ssamhid\nimport ssam.ssamwire\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
FIRNLIB="$L0" "$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "lib compiles with --profile=kernel" \
    || { bad "lib does not compile with --profile=kernel"; head -5 "$T/k.err"; }
FIRNLIB="$L0" "$FIRNC" tools/ssam/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds" || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0 (no panic)" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 60 ] && ok "oracle: $nok promises OK (>= 60)" || bad "oracle: only $nok OK (< 60)"
    pass=$((pass+nok))
fi

mutate() { # name file sed-expression
    local name=$1 file=$2 expr=$3
    local L="$T/lib-$name"
    farm "$L"
    for f in lib/ssam/*.fi; do
        if [ "$(basename "$f")" = "$file" ]; then
            sed -e "$expr" "$f" > "$L/ssam/$file"
        else
            ln -s "$ROOT/$f" "$L/ssam/$(basename "$f")"
        fi
    done
    if cmp -s "lib/ssam/$file" "$L/ssam/$file"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/ssam/oracle.fi -o "$T/o-$name" 2>/dev/null; then
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
mutate crc_init       ssamwire.fi 's/^const CRC_INIT: u64 = 0xFFFF/const CRC_INIT: u64 = 0/'
mutate crc_poly       ssamwire.fi 's/^const CRC_POLY: u64 = 0x1021/const CRC_POLY: u64 = 0x8005/'
mutate syn_order      ssamwire.fi 's/^const SYN0: u64 = 0xAA/const SYN0: u64 = 0x55/'
mutate frame_ack      ssamwire.fi 's/^const FRAME_ACK: u64 = 0x40/const FRAME_ACK: u64 = 0x04/'
mutate rqid_skip      ssamwire.fi 's/    if n <= EVENT_RQID_MAX {/    if false {/'
mutate source_id      ssamwire.fi 's/octets.st8(dst, 11, TID_HOST)/octets.st8(dst, 11, TID_SAM)/'
mutate dup_check      ssamlink.fi 's/if g(l, L_LAST_OK) != 0 \&\& g(l, L_LAST_SEQ) == seq {/if false {/'
mutate ack_seq        ssamlink.fi 's/queue_ack(l, seq)/queue_ack(l, 0)/'
mutate payload_crc    ssamlink.fi 's/if ssamwire.crc16(buf + ssamwire.FRAME_HDR_LEN, len) != octets.ld16(buf, ssamwire.FRAME_HDR_LEN + len) {/if false {/'
mutate header_crc     ssamlink.fi 's/if ssamwire.crc16(buf + 2, 4) != octets.ld16(buf, 6) {/if false {/'
mutate nak_on_crc     ssamlink.fi 's/            queue_nak(l)//'
mutate rqid_match     ssamlink.fi 's/ || octets.ld16(p, 5) != g(l, L_PEND_RQID)//'
mutate ack_match      ssamlink.fi 's/ \&\& seq == g(l, L_PEND_SEQ)//'
mutate max_tries      ssamlink.fi 's/^const MAX_TRIES: u64 = 3/const MAX_TRIES: u64 = 9/'
mutate ack_timeout    ssamlink.fi 's/^const ACK_TIMEOUT_MS: u64 = 250/const ACK_TIMEOUT_MS: u64 = 25/'
mutate event_overflow ssamlink.fi 's/if ev_avail(l) >= EV_SLOTS {/if false {/'
mutate event_size     ssamlink.fi 's/if dlen > EV_DATA_MAX {/if false {/'
mutate payload_max    ssamlink.fi 's/if len > PAYLOAD_MAX {/if false {/'
mutate nak_resend     ssamlink.fi 's/            resend(l, now)\n        }\n        return\n    }\n    if kind == wire.FRAME_DATA_SEQ/XX/; s/bump(l, C_NAK_RX)/bump(l, C_NAK_RX)\n        return/'
mutate hid_type       ssamhid.fi 's/ \&\& octets.ld8(p, 1) == HID_DT_HID//'
mutate hid_count      ssamhid.fi 's/        \&\& octets.ld8(p, 5) == 1 \&\& octets.ld8(p, 6) == HID_DT_REPORT/        \&\& octets.ld8(p, 6) == HID_DT_REPORT/'
mutate slice_bounds   ssamhid.fi 's/ \&\& octets.ld32(p, 5) <= n - SLICE_HDR_LEN//'
mutate event_rqid     ssamhid.fi 's/octets.st16(dst, 2, tc)/octets.st16(dst, 2, 0)/'
mutate status_ok      ssamhid.fi 's/ \&\& octets.ld8(p, 0) == 0$/ \&\& true/'

echo "ssam: $pass promises, $fail errors"
[ "$fail" = 0 ]
