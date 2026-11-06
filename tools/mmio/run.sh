#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/tmpdir.sh
D=$(mktemp -d)
osum_tmp_guard "${1:-}" "$D"
pass=0
fail=0
ok() { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
C=tools/mmio/check.py

mk() {
    rm -rf "$D/t"
    mkdir -p "$D/t/lib/libc" "$D/t/kernel/lib" "$D/t/kernel/drv/x" "$D/t/kernel/acpi" "$D/t/kernel/bus" "$D/t/tools/mmio"
    cp lib/libc/octets.fi lib/libc/numeric.fi lib/libc/regio.fi "$D/t/lib/libc/"
    cp kernel/lib/kstate.fi "$D/t/kernel/lib/"
    : > "$D/t/tools/mmio/plain-ok.txt"
}
expect() {
    local name=$1 want=$2 needle=${3:-}
    out=$(python3 -I $C --root "$D/t" 2>&1); rc=$?
    if [ "$want" = fail ] && [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "$needle"; then ok "$name"
    elif [ "$want" = pass ] && [ $rc -eq 0 ]; then ok "$name"
    else bad "$name (rc=$rc: $(printf '%s' "$out" | head -2 | tr '\n' ' '))"; fi
}

echo "== 1. real tree =="
out=$(python3 -I $C --root . 2>&1) && ok "kernel/drv, kernel/acpi, kernel/bus use only volatile access or listed plain access" || bad "real tree: $out"

echo "== 2. counter-proofs =="
mk
printf 'import libc.octets\nfn f(p: u64) {\n    octets.zero(p, 8)\n}\n' > "$D/t/kernel/drv/x/dma.fi"
expect "plain zero in kernel/drv without entry is caught" fail "kernel/drv/x/dma.fi"
printf 'kernel/drv/x/dma.fi\tCPU-only scratch buffer\n' > "$D/t/tools/mmio/plain-ok.txt"
expect "plain zero in kernel/drv with entry passes" pass
printf 'kernel/drv/x/dma.fi\t\n' > "$D/t/tools/mmio/plain-ok.txt"
expect "entry without reason is caught" fail "without reason"
printf 'kernel/drv/x/gone.fi\tx\n' > "$D/t/tools/mmio/plain-ok.txt"
expect "entry for missing file is caught" fail "missing file"
mk
printf 'import libc.octets\nfn f(p: u64) -> u64 {\n    return octets.le16(p)\n}\n' > "$D/t/kernel/acpi/tbl.fi"
expect "plain le16 in kernel/acpi without entry is caught" fail "kernel/acpi/tbl.fi"
mk
printf 'import libc.octets\nfn f(p: u64) -> u64 {\n    return octets.ld32(p, 0)\n}\n' > "$D/t/kernel/bus/cfg.fi"
expect "plain ld32 in kernel/bus without entry is caught" fail "kernel/bus/cfg.fi"
mk
printf 'import libc.numeric\nfn f(a: u64, b: u64) -> u64 {\n    return numeric.umin(a, b)\n}\n' > "$D/t/kernel/drv/x/arith.fi"
expect "pure arithmetic libc call needs no entry" pass
mk
printf 'fn f() {\n}\n' > "$D/t/kernel/drv/x/idle.fi"
printf 'kernel/drv/x/idle.fi\tnothing plain here\n' > "$D/t/tools/mmio/plain-ok.txt"
expect "stale entry is caught" fail "stale"
mk
sed -i 's/__mmio_read8((p + o) as \*mut u8)/*((p + o) as *mut u8)/' "$D/t/lib/libc/regio.fi"
expect "regio.read8_at inlined to plain is caught" fail "regio.fi:read8_at"
mk
sed -i '/^fn get8/,/^}/c\fn get8(p: u64) -> u64 {\n    return (*(p as *mut u8)) as u64\n}' "$D/t/kernel/lib/kstate.fi"
expect "kstate.get8 inlined to plain is caught" fail "kstate.fi:get8"

mk
sed -i 's/(v \& 0xFF) as u8/v as u8/' "$D/t/lib/libc/regio.fi"
expect "regio.write8 without mask is caught" fail "regio.fi:write8"
mk
sed -i 's/(v \& 0xFFFF) as u16/v as u16/' "$D/t/lib/libc/regio.fi"
expect "regio.write16 without mask is caught" fail "regio.fi:write16"
mk
sed -i 's/(v \& 0xFFFFFFFF) as u32/v as u32/' "$D/t/lib/libc/regio.fi"
expect "regio.write32 without mask is caught" fail "regio.fi:write32"
mk
sed -i 's/(v \& 255) as u8/v as u8/' "$D/t/lib/libc/regio.fi"
expect "regio.write8_at without mask is caught" fail "regio.fi:write8_at"

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
