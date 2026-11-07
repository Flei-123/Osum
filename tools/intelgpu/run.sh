#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
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

for m in ids regs bits mode timing edid aux state dump; do
    printf 'import gpu.intel.%s\nfn main() -> i32 {\n    return 0\n}\n' "$m" > "$T/k_$m.fi"
    "$FIRNC" --profile=kernel -c "$T/k_$m.fi" -o "$T/k_$m.o" 2> "$T/k.err" \
        && ok "gpu.intel.$m compiles with --profile=kernel" \
        || { bad "gpu.intel.$m does not compile with --profile=kernel"; head -5 "$T/k.err"; }
done

"$FIRNC" tools/intelgpu/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds" || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 150 ] && ok "oracle: $nok promises OK (>= 150)" || bad "oracle: only $nok OK (< 150)"
    pass=$((pass+nok))
fi

mutate() {
    local name=$1 file=$2 expr=$3
    local L="$T/lib-$name"
    mkdir -p "$L/gpu/intel"
    for d in lib/*; do
        [ "$(basename "$d")" = gpu ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    for d in lib/gpu/*; do
        [ "$(basename "$d")" = intel ] || ln -s "$ROOT/$d" "$L/gpu/$(basename "$d")"
    done
    for f in lib/gpu/intel/*.fi; do
        cp "$f" "$L/gpu/intel/$(basename "$f")"
    done
    sed -i -e "$expr" "$L/gpu/intel/$file.fi"
    if cmp -s "lib/gpu/intel/$file.fi" "$L/gpu/intel/$file.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/intelgpu/oracle.fi -o "$T/o-$name" 2>/dev/null; then
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

mutate id_mask       ids    's/0x2c042cca6cec4c44/0x2c042cca6cec4c45/'
mutate id_extra      ids    's/device == KBL_EXTRA/device == 0x87c1/'
mutate id_vendor     ids    's/if vendor != VENDOR_INTEL {/if false {/'
mutate off_cdclk     regs   's/CDCLK_CTL: u64 = 0x46000/CDCLK_CTL: u64 = 0x46004/'
mutate off_link_m    regs   's/T_LINK_M1: u64 = 0x40/T_LINK_M1: u64 = 0x30/'
mutate off_htotal    regs   's/T_HTOTAL: u64 = 0x0/T_HTOTAL: u64 = 0x8/'
mutate off_aux_data  regs   's/AUX_DATA_A: u64 = 0x64014/AUX_DATA_A: u64 = 0x64018/'
mutate plus_one      timing 's/return (v \& LOW16) + 1/return (v \& LOW16)/'
mutate mn_rounding   timing 's/(link_m \* symbol_khz + link_n \/ 2) \/ link_n/(link_m * symbol_khz) \/ link_n/'
mutate mn_swapped    timing 's/(link_m \* symbol_khz + link_n \/ 2) \/ link_n/(link_n * symbol_khz + link_m \/ 2) \/ link_m/'
mutate pll_shift     timing 's/DPLL_FIELD_BITS: u64 = 6/DPLL_FIELD_BITS: u64 = 5/'
mutate tu_field      timing 's/TU_SHIFT: u64 = 25/TU_SHIFT: u64 = 24/'
mutate rate_table    timing 's/return 270000/return 270001/'
mutate refresh_unit  mode   's/KHZ_TO_MHZ_REFRESH: u64 = 1000000/KHZ_TO_MHZ_REFRESH: u64 = 100000/'
mutate edid_sum      edid   's/return (sum \& 0xff) == 0/return true/'
mutate edid_header   edid   's/if octets.ld8(p, 0) != 0 || octets.ld8(p, 7) != 0 {/if false {/'
mutate edid_fill     edid   's/if octets.ld8(p, i) != HEADER_FILL {/if false {/'
mutate edid_hact     edid   's/octets.ld8(p, d + 4) \& 0xf0) << 4)/octets.ld8(p, d + 4) \& 0xf0) << 3)/'
mutate edid_letters  edid   's/LETTER_BASE: u64 = 64/LETTER_BASE: u64 = 65/'
mutate edid_pclk     edid   's/PCLK_UNIT_KHZ: u64 = 10/PCLK_UNIT_KHZ: u64 = 100/'
mutate edid_size     edid   's/CM_TO_MM: u64 = 10/CM_TO_MM: u64 = 1/'
mutate send_word     bits   's/AUX_CLOCK_BITS: u64 = 0x23f/AUX_CLOCK_BITS: u64 = 0x23e/'
mutate send_timeout  bits   's/AUX_TIMEOUT_MAX: u64 = 0x3/AUX_TIMEOUT_MAX: u64 = 0x2/'
mutate pack_order    aux    's/v = v << 8/v = (v >> 8) | (v << 24)/'
mutate recv_pause    aux    's/us(RECV_ERR_PAUSE_US)//'
mutate nack_ok       aux    's/    return E_NACK/    return E_OK/'
mutate defer_nack    aux    's/if (code \& REPLY_DEFER_MASK) != 0 {/if false {/'
mutate defer_retry   aux    's/MAX_DEFER_RETRIES: u64 = 7/MAX_DEFER_RETRIES: u64 = 1/'
mutate send_retry    aux    's/MAX_SEND_RETRIES: u64 = 5/MAX_SEND_RETRIES: u64 = 1/'
mutate no_mot        aux    's/REQ_I2C_READ | REQ_MOT$/REQ_I2C_READ/'
mutate no_offset_mot aux    's/REQ_I2C_WRITE | REQ_MOT/REQ_I2C_WRITE/'
mutate size_check    aux    's/if size == 0 || size > MAX_MSG {/if false {/'
mutate busy_check    aux    's/return E_BUSY/return E_OK/'
mutate short_reply   aux    's/var take: u64 = got - 1/var take: u64 = chunk/'
mutate cdclk_table   state  's/return 450000$/return 450001/'
mutate bpc_table     state  's/return 6$/return 7/'
mutate lanes_plus    state  's/bits.DDI_LANES_MASK) + 1/bits.DDI_LANES_MASK)/'
mutate stride_unit   bits   's/PLANE_STRIDE_UNIT: u64 = 0x40/PLANE_STRIDE_UNIT: u64 = 0x20/'
mutate pp_shift      bits   's/PP_DELAY_SHIFT: u64 = 0x10/PP_DELAY_SHIFT: u64 = 0x11/'

echo "INTELGPU: $pass passed, $fail failed"
[ "$fail" = 0 ]
