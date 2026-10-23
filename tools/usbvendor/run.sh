#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
T=$(mktemp -d /tmp/usbvendor.XXXXXX)
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  OK    $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL  $1"; }
[ -x "$FIRNC" ] || bash vendor/firn/fetch-firnc.sh > /dev/null 2>&1

printf 'import usbnet.ax88772\nfn main() -> i32 {\n    return 0\n}\n' > "$T/k.fi"
FIRNLIB="$ROOT/lib" "$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "ax88772 compiles with --profile=kernel" || { bad "ax88772 does not compile for the kernel"; head -5 "$T/k.err"; }

run_oracle() {
    local lib=$1 out=$2
    FIRNLIB="$lib" "$FIRNC" tools/usbvendor/oracle.fi -o "$T/oracle" > "$T/o.err" 2>&1 || { head -8 "$T/o.err"; return 2; }
    "$T/oracle" > "$out" 2>&1
}

run_oracle "$ROOT/lib" "$T/out.txt"
nok=$(grep -c '^OK' "$T/out.txt"); nfail=$(grep -c '^FAIL' "$T/out.txt")
sed 's/^/        /' "$T/out.txt" | grep FAIL
[ "$nfail" = 0 ] && [ "$nok" -ge 25 ] && ok "oracle: $nok promises hold" || bad "oracle: $nok ok, $nfail fail"

mutate() {
    local name=$1 expr=$2
    rm -rf "$T/mut"; mkdir -p "$T/mut"; cp -r lib/. "$T/mut/"
    sed -i "$expr" "$T/mut/usbnet/ax88772.fi"
    cmp -s lib/usbnet/ax88772.fi "$T/mut/usbnet/ax88772.fi" && { bad "mutation '$name' changed nothing"; return; }
    run_oracle "$T/mut" "$T/mut.txt"
    if grep -q '^FAIL' "$T/mut.txt"; then ok "counter-proof: oracle goes red without '$name' ($(grep -c '^FAIL' "$T/mut.txt") promises fail)"
    else bad "counter-proof: oracle stays green without '$name'"; fi
}
mutate "complement check" 's/if size != inv { return 0 }//'
mutate "length bound" 's/if pos + HDR + (size as usize) > len { return 0 }//'
mutate "512 pad word" 's/if (total \& (MAXPACKET - 1)) == 0 {/if false {/'
mutate "16 bit padding" 's/((l + 1) \& 0xFFFFFFFE)/l/'

echo "USBVENDOR: $pass passed, $fail failed"
[ "$fail" = 0 ]
