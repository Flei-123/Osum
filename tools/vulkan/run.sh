#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vulkan/run.sh -- libvulkan.so.1 (Firn, lib/vulkan) against lavapipe: same C client, byte-identical readbacks, mutation counter-proofs.
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
LVP=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
. tools/lib/tmpdir.sh; osum_tmp_guard "${1:-}" "$D"
pass=0; fail=0
ck() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
FIRNC=vendor/firn/bin/firnc
python3 -I tools/vulkan/genproc.py "$PWD" > /dev/null
git diff --quiet -- lib/vulkan/vkproc.fi && ck "vkproc.fi is generated from the exports (no drift)" ok || ck "vkproc.fi is generated from the exports (no drift)" no
gcc -O1 -Wall -o "$D/client" tools/vulkan/client.c -ldl && ck "client builds" ok || { ck "client builds" no; exit 1; }
FIRNLIB="$PWD/lib" $FIRNC --shared -o "$D/libvulkan.so.1" lib/vulkan/libvulkan.fi > "$D/build.log" 2>&1 && ck "firnc --shared builds libvulkan.so.1" ok || { ck "firnc --shared builds libvulkan.so.1" no; grep -v '^warning' "$D/build.log" | head -20; exit 1; }
n=$(nm -D "$D/libvulkan.so.1" | grep -c ' T vk')
[ "$n" -ge 55 ] && ck "at least 55 vk* symbols exported ($n)" ok || ck "at least 55 vk* symbols exported ($n)" no
VK_DRIVER_FILES=$LVP "$D/client" libvulkan.so.1 1 > "$D/lvp.txt" 2>&1
grep -q "^VK DONE bad=0" "$D/lvp.txt" && ck "reference lavapipe: client passes" ok || ck "reference lavapipe: client passes" no
stdbuf -o0 "$D/client" "$D/libvulkan.so.1" > "$D/ours.txt" 2>&1
grep -q "^VK DONE bad=0" "$D/ours.txt" && ck "OrientOS ICD: client passes" ok || { ck "OrientOS ICD: client passes" no; grep FAIL "$D/ours.txt" | head; }
c=$(grep -c "^VK ok" "$D/ours.txt"); [ "$c" -ge 25 ] && ck "at least 25 client checks ok ($c)" ok || ck "at least 25 client checks ok ($c)" no
grep "^VK case" "$D/lvp.txt" > "$D/lvp.cases"; grep "^VK case" "$D/ours.txt" > "$D/ours.cases"
[ "$(wc -l < "$D/ours.cases")" -ge 5 ] && cmp -s "$D/lvp.cases" "$D/ours.cases" && ck "readback hashes == lavapipe (5 cases, byte identical)" ok || { ck "readback hashes == lavapipe (5 cases, byte identical)" no; diff "$D/lvp.cases" "$D/ours.cases" | head -6; }
mutate() {
    local name=$1 file=$2 expr=$3
    rm -rf "$D/m"; mkdir -p "$D/m"; cp -r lib "$D/m/lib"
    sed -i "$expr" "$D/m/lib/vulkan/$file"
    if cmp -s "lib/vulkan/$file" "$D/m/lib/vulkan/$file"; then ck "counter-proof $name: mutation applied" no; return; fi
    FIRNLIB="$D/m/lib" $FIRNC --shared -o "$D/m/libvulkan.so.1" "$D/m/lib/vulkan/libvulkan.fi" > "$D/m/build.log" 2>&1 || { ck "counter-proof $name: mutant builds" no; return; }
    timeout 60 stdbuf -o0 "$D/client" "$D/m/libvulkan.so.1" > "$D/m/out.txt" 2>&1
    grep "^VK case" "$D/m/out.txt" > "$D/m/cases"
    cmp -s "$D/lvp.cases" "$D/m/cases" && ck "counter-proof $name: mutant must differ from lavapipe" no || ck "counter-proof $name: mutant differs from lavapipe" ok
}
mutate "no rounding" vkexec.fi 's/v \* 255.0f + 0.5f/v * 255.0f/'
mutate "no BGRA swizzle" vkexec.fi 's/if format == 44 as u32 { return b/if format == 99 as u32 { return b/'
mutate "ignored row length" vkexec.fi 's/if rowlen == 0 as u64 { rowlen = w }/rowlen = w/'
mutate "wrong copy offset" vkexec.fi 's/rt.mem_copy(dp + d_o, sp + so, n as usize)/rt.mem_copy(dp + d_o, sp, n as usize)/'
mutate "fill skipped" vkexec.fi 's/if op == vkcmd.OP_FILL { exec_fill(rec) }//'
echo "VULKAN: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
