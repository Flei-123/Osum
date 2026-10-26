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

MODULES="record quirk track api inmode"
for m in $MODULES; do
    [ -f "lib/touchev/$m.fi" ] && ok "lib/touchev/$m.fi exists" || bad "lib/touchev/$m.fi missing"
    printf 'import touchev.%s\nfn main() -> i32 {\n    return 0\n}\n' "$m" > "$T/k-$m.fi"
    "$FIRNC" --profile=kernel -c "$T/k-$m.fi" -o "$T/k-$m.o" 2> "$T/k-$m.err" \
        && ok "touchev.$m compiles with --profile=kernel" \
        || { bad "touchev.$m does not compile with --profile=kernel"; head -5 "$T/k-$m.err"; }
done

stray=$(grep -n '//' lib/touchev/*.fi | grep -v 'SPDX-License-Identifier: GPL-2.0-only' | wc -l)
[ "$stray" = 0 ] && ok "lib/touchev has no comments besides SPDX" || bad "lib/touchev has $stray comment lines"

[ -f tools/touchev/oracle.fi ] && ok "oracle.fi exists" || bad "oracle.fi missing"
"$FIRNC" tools/touchev/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds against lib/touchev" \
    || { bad "oracle does not build"; head -10 "$T/o.err"; }

if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    rc=$?
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$rc" = 0 ] && ok "oracle exits 0" || bad "oracle exit code $rc"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 70 ] && ok "oracle: $nok promises OK (>= 70)" || bad "oracle: only $nok OK (< 70)"
    pass=$((pass+nok))
fi

mutate() {
    local name=$1 file=$2 expr=$3
    local L="$T/lib-$name"
    mkdir -p "$L/touchev"
    for d in lib/*; do
        [ "$(basename "$d")" = touchev ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    cp lib/touchev/*.fi "$L/touchev/"
    sed -i -e "$expr" "$L/touchev/$file.fi"
    if cmp -s "lib/touchev/$file.fi" "$L/touchev/$file.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/touchev/oracle.fi -o "$T/o-$name" 2>/dev/null; then
        bad "control $name: mutated oracle does not build"
        return
    fi
    local nf rc
    nf=$("$T/o-$name" 2>&1 | grep -c '^FAIL')
    "$T/o-$name" > /dev/null 2>&1
    rc=$?
    if [ "$nf" -gt 0 ] || [ "$rc" != 0 ]; then
        ok "control $name: oracle goes red ($nf FAIL, exit $rc)"
    else
        bad "control $name: oracle stays green on a broken lib"
    fi
}

mutate noclamplo   track 's/if c < lo { c = lo }//'
mutate noclamphi   track 's/if c > hi { c = hi }//'
mutate normoff     track 's/(c - lo) \* NORM_MAX) \/ (hi - lo)/(c - lo) * NORM_MAX) \/ (hi - lo + 1)/'
mutate noinvx      track 's/if (d_quirks\[dev as usize\] & quirk.Q_INVERT_X) != 0 { return 65535 - n }//'
mutate noinvy      track 's/if (d_quirks\[dev as usize\] & quirk.Q_INVERT_Y) != 0 { return 65535 - n }//'
mutate noswap      track 's/if (d_quirks\[dev as usize\] & quirk.Q_SWAP_XY) != 0 {/if false {/'
mutate nosingle    track 's/ && call > 0 { return }/ \&\& call > 100 { return }/'
mutate nopalm      track 's/if confident == 0 && (d_quirks\[dev as usize\] & quirk.Q_NO_CONFIDENCE) == 0 { fl = record.F_PALM }//'
mutate noconfquirk track 's/ && (d_quirks\[dev as usize\] & quirk.Q_NO_CONFIDENCE) == 0//'
mutate noignore    track 's/if (d_quirks\[dev as usize\] & quirk.Q_IGNORE) != 0 { return 0 }//'
mutate upasmove    track 's/emit_slot(dev, record.T_UP, s)/emit_slot(dev, record.T_MOVE, s)/'
mutate alwaysmove  track 's/if s_x\[i\] != f_x\[fk\] || /if true || /'
mutate nopressmove track 's/ || s_p\[i\] != f_p\[fk\]//'
mutate idmatch     track 's/if s_used\[k\] != 0 && s_id\[k\] == id { return s }/if s_used[k] != 0 { return s }/'
mutate fewslots    track 's/const MAX_SLOT: u64 = 10/const MAX_SLOT: u64 = 8/'
mutate sharedslots track 's/return (dev \* MAX_SLOT + slot) as usize/return slot as usize/'
mutate pxraw       track 's/return (((n as i64) \* (size - 1)) \/ NORM_MAX) as u64/return n/'
mutate nolostcount track 's/d_lost\[dev as usize\] = d_lost\[dev as usize\] + 1/d_lost[dev as usize] = d_lost[dev as usize]/'
mutate nohover     track 's/if tip != 0 { pr = clamp16(pressure) } else { fl = record.F_HOVER }/if tip != 0 { pr = clamp16(pressure) }/'
mutate nopenup     track 's/emit(dev, record.T_UP, 0, record.D_PEN, p_fl\[d\], p_x\[d\], p_y\[d\], 0, 0)//'
mutate nobarrel    track 's/if barrel != 0 { fl = fl | record.F_BARREL }//'
mutate slotusedoff track 's/return s_used\[si(dev, s)\] != 0$/return true/'
mutate slotxoff    track 's/return s_x\[si(dev, s)\]$/return s_y[si(dev, s)]/'
mutate slotidoff   track 's/return s_id\[si(dev, s)\]$/return s_x[si(dev, s)]/'
mutate fewdev      track 's/const MAX_DEV: u64 = 8/const MAX_DEV: u64 = 4/'
mutate imtype      inmode 's/st8(out, at, (REPORT_FEATURE << 4) | low)/st8(out, at, (2 << 4) | low)/'
mutate imopcode    inmode 's/const OP_SET_REPORT: u64 = 3/const OP_SET_REPORT: u64 = 2/'
mutate imlong      inmode 's/if rid >= RID_LONG {$/if rid > 100 {/'
mutate imsize      inmode 's/var size: u64 = 2 + n/var size: u64 = 1 + n/'
mutate imsizeid    inmode 's/        size = size + 1/        size = size/'
mutate imbits      inmode 's/st8(buf, at \/ 8, ld8(buf, at \/ 8) | (1 << (at % 8)))/st8(buf, at \/ 8, 1 << (at % 8))/'
mutate imusb       inmode 's/return (REPORT_FEATURE << 8) | rid/return (2 << 8) | rid/'
mutate rectyoff    record 's/const O_YN: u64 = 6/const O_YN: u64 = 4/'
mutate nosignext   record 's/if v >= 0x8000 { return (v as i64) - 0x10000 }//'
mutate badmagic    record 's/const MAGIC: u64 = 0x31564554/const MAGIC: u64 = 0x31564555/'
mutate timeoff     record 's/const O_TIME: u64 = 16/const O_TIME: u64 = 18/'
mutate lostbyte    record 's/st8(p, o + 1, v >> 8)/st8(p, o + 1, v)/'
mutate nopidwild   quirk  's/if word(row, 2) != ID_ANY && word(row, 2) != pid { return false }/if word(row, 2) != pid { return false }/'
mutate orlost      quirk  's/flags = flags | word(i, 3)/flags = word(i, 3)/'
mutate novidwild   quirk  's/if word(row, 1) != ID_ANY && word(row, 1) != vid { return false }/if word(row, 1) != vid { return false }/'
mutate nobus       quirk  's/if word(row, 0) != B_ANY && word(row, 0) != bus { return false }/if false { return false }/'
mutate nospecific  quirk  's/if best == NO_ROW || s > best_s {/if best == NO_ROW {/'
mutate nodupcheck  quirk  's/if same_key(i, bus, vid, pid) { return NO_ROW }//'
mutate startflag   quirk  's/0, 0x045e, 0x0c32, 16/0, 0x045e, 0x0c32, 0/'
mutate nodrop      quirk  's/ROWS\[base\] = B_FREE//'
mutate nomagicchk  api    's/if len < record.HEADER_BYTES || !record.magic_ok(buf) {/if len < record.HEADER_BYTES {/'
mutate notruncchk  api    's/ || record.snapshot_bytes(count) > len//'
mutate nodroppedsum api   's/s_dropped = s_dropped + (s_count - s_pos) + record.header_dropped(buf)/s_dropped = s_dropped/'
mutate nogestfilt  api    's/if record.get_type(base(), s_cur) == record.T_GESTURE {/if true {/'
mutate nobadcount  api    's/s_bad = s_bad + 1//'
mutate noclose     api    's/^    s_open = 0$/    s_open = 1/'

echo "touchev: $pass ok, $fail fail"
[ "$fail" = 0 ]
