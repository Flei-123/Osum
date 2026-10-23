#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ax88772drv/run.sh -- AX88772 driver glue against a FAKE device (host, no QEMU: QEMU has no AX88772 model).
# Checks the bring-up request sequence, the device rules (MAC only after the reset sequence, RX only with SO + RE) and the bulk
# framing in both directions, cmp-exact against ref.py. Constants come from protocol knowledge, not from a real chip.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
T=$(mktemp -d /tmp/ax88772drv.XXXXXX)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  OK    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh > /dev/null 2>&1

python3 -I tools/ax88772drv/ref.py > "$T/want.txt"

run_fake() {
    local lib=$1 out=$2
    FIRNLIB="$lib" "$FIRNC" --profile=app tools/ax88772drv/test.fi -o "$T/fake" > "$T/b.err" 2>&1 || { head -8 "$T/b.err"; return 2; }
    "$T/fake" > "$out" 2>&1
}

printf 'import usbnet.ax88772_drv\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
FIRNLIB="$ROOT/lib" "$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "ax88772_drv compiles with --profile=kernel" || { bad "ax88772_drv does not compile for the kernel"; head -5 "$T/k.err"; }

run_fake "$ROOT/lib" "$T/got.txt"
if diff -q "$T/want.txt" "$T/got.txt" > /dev/null; then ok "fake device: $(wc -l < "$T/got.txt") serial lines equal the Python reference"
else bad "fake device output differs from ref.py"; diff "$T/want.txt" "$T/got.txt" | head -10; fi
grep -q '^ax: step 0 mac 2 19 36 53 70 87$' "$T/got.txt" && ok "bring-up ends at step 0 with the fake MAC" || bad "bring-up did not finish"
[ "$(grep -c '^ax: pause 150000$' "$T/got.txt")" = 3 ] && ok "three reset pauses of 150 ms" || bad "reset pauses"
[ "$(grep -c '^ax: tx .* ok 1$' "$T/got.txt")" = 4 ] && ok "four TX frames accepted by the independent device parser" || bad "TX frames"
[ "$(grep -c '^ax: rx [0-9]* ' "$T/got.txt")" = 4 ] && ok "four RX frames split out of one bulk transfer" || bad "RX frames"

mutate() {
    local name=$1 file=$2 expr=$3
    rm -rf "$T/mut"; mkdir -p "$T/mut"; cp -r lib/. "$T/mut/"
    sed -i "$expr" "$T/mut/usbnet/$file"
    cmp -s "lib/usbnet/$file" "$T/mut/usbnet/$file" && { bad "mutation '$name' changed nothing"; return; }
    run_fake "$T/mut" "$T/mut.txt"
    if diff -q "$T/want.txt" "$T/mut.txt" > /dev/null; then bad "counter-proof: gate stays green without '$name'"
    else ok "counter-proof: gate goes red without '$name'"; fi
}
mutate "third reset" ax88772_drv.fi '/ax88772.SWRESET_IPRL) {/,+0d'
mutate "RX on" ax88772_drv.fi 's/ax88772.CMD_WRITE_RX_CTL, ax88772.RXCTL_DEFAULT/ax88772.CMD_WRITE_RX_CTL, 0/'
mutate "receive enable in medium" ax88772.fi 's/MEDIUM_DEFAULT: u64 = 0x0336/MEDIUM_DEFAULT: u64 = 0x0236/'
mutate "header complement" ax88772.fi 's/return l | (((~l) \& SIZE_MASK) << 16)/return l | (l << 16)/'
mutate "512 pad word" ax88772.fi 's/if (total \& (MAXPACKET - 1)) == 0 {/if false {/'

echo "AX88772DRV: $pass passed, $fail failed"
[ "$fail" = 0 ]
