#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vkguest/run.sh <workdir from tools/linuxapps/prep-firefox.sh> -- libvulkan.so.1 (Firn) loads in the Osum dynamic loader and renders the 17 draw scenes; guest image hashes == host run.
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
. tools/lib/tmpdir.sh; osum_tmp_guard "${1:-}" "$D"
export FIRNLIB="$(pwd)/lib"
. tools/lib/firnenv.sh
pass=0; fail=0
ck() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
$FIRNC --shared -o "$D/libvulkan.so.1" lib/vulkan/libvulkan.fi > "$D/build.log" 2>&1 && ck "firnc --shared builds libvulkan.so.1" ok || { ck "firnc --shared builds libvulkan.so.1" no; exit 1; }
mkdir -p "$D/mut"; cp -r lib "$D/mut/lib"
sed -i 's/if rt.ld64(rs, R_HASVP) != 0 as u64 {/if rt.ld64(rs, R_HASVP) == 99 as u64 {/' "$D/mut/lib/vulkan/vkrender.fi"
cmp -s lib/vulkan/vkrender.fi "$D/mut/lib/vulkan/vkrender.fi" && ck "mutant differs from source" no || ck "mutant differs from source" ok
FIRNLIB="$D/mut/lib" $FIRNC --shared -o "$D/libvulkan_mut.so" "$D/mut/lib/vulkan/libvulkan.fi" > "$D/mut.log" 2>&1 && ck "mutant builds" ok || ck "mutant builds" no
mkdir -p "$D/inc"; ln -s /usr/include/vulkan "$D/inc/vulkan"; ln -s /usr/include/vk_video "$D/inc/vk_video"
musl-gcc -O1 -I"$D/inc" -o "$D/draw" tools/vulkan/draw.c && ck "musl draw client builds (dynamic)" ok || { ck "musl draw client builds (dynamic)" no; exit 1; }
gcc -O1 -o "$D/hostdraw" tools/vulkan/draw.c -ldl
mkdir -p "$D/spv"
for sh in tri.vert tri.frag push.frag depth.vert quad.vert quad.frag inst.vert inst.frag ubo.vert ubo.frag; do
    glslangValidator -V "tools/vulkan/shaders/$sh" -o "$D/spv/$sh.spv" > /dev/null 2>&1 && spirv-opt --inline-entry-points-exhaustive --eliminate-dead-functions --eliminate-local-multi-store "$D/spv/$sh.spv" -o "$D/spv/$sh.opt" || ck "shader $sh compiles" no
done
for sh in fui_rect.vert fui_rect.frag; do
    glslangValidator -V "tools/gfx/shaders/$sh" -o "$D/spv/$sh.spv" > /dev/null 2>&1 && spirv-opt --inline-entry-points-exhaustive --eliminate-dead-functions --eliminate-local-multi-store "$D/spv/$sh.spv" -o "$D/spv/$sh.opt" || ck "shader $sh compiles" no
done
"$D/hostdraw" "$D/libvulkan.so.1" 0 - "$D/spv" > "$D/host.txt" 2>&1
grep -q "^VK DONE bad=0" "$D/host.txt" && ck "host run passes" ok || ck "host run passes" no
grep "^VK img" "$D/host.txt" | sort > "$D/host.img"
[ "$(wc -l < "$D/host.img")" -ge 20 ] && ck "host run printed 20 image hashes (17 scenes + 3 swapchain frames)" ok || ck "host run printed 20 image hashes (17 scenes + 3 swapchain frames)" no
grep "^VK sink" "$D/host.txt" | sort > "$D/host.sink"
grep -v '^/etc/inittab' "$WD/fxrun/spec.txt" > "$D/spec.txt"
{
    printf '/vk/@755\n/vk/spv/@755\n/vk/draw=%s@755\n/vk/libvulkan.so.1=%s@755\n/vk/libvulkan_mut.so=%s@755\n' "$D/draw" "$D/libvulkan.so.1" "$D/libvulkan_mut.so"
    for f in "$D"/spv/*.opt; do printf '/vk/spv/%s=%s@644\n' "$(basename "$f")" "$f"; done
} >> "$D/spec.txt"
SPEC="$D/spec.txt" BLOCKS=${BLOCKS:-1000000} TMO=${TMO:-900} bash tools/linuxapps/run.sh "$WD" tools/vkguest/guest.sh "$D/out" > "$D/run.log" 2>&1
S="$D/out/ser.clean"
grep -aq "^VKG rc=0" "$S" && ck "guest: draw client exits 0 (dlopen of libvulkan.so.1)" ok || ck "guest: draw client exits 0 (dlopen of libvulkan.so.1)" no
awk '/^VKG guest start/{a=1;next} /^VKG rc=/{a=0} a && /^VK img/' "$S" | sort > "$D/guest.img"
[ "$(wc -l < "$D/guest.img")" -ge 20 ] && ck "guest: 20 image hashes printed" ok || ck "guest: 20 image hashes printed" no
awk '/^VKG guest start/{a=1;next} /^VKG rc=/{a=0} a && /^VK sink/' "$S" | sort > "$D/guest.sink"
[ "$(wc -l < "$D/guest.sink")" -eq 3 ] && cmp -s "$D/host.sink" "$D/guest.sink" && ck "guest: present sink (wl_shm-style shared memory) == host, 3 frames" ok || ck "guest: present sink (wl_shm-style shared memory) == host, 3 frames" no
awk '/^VKG guest start/{a=1;next} /^VKG rc=/{a=0} a && /^VK ok sink rows/' "$S" | wc -l | grep -qx 3 && ck "guest: sink rows == swapchain readback (3 frames)" ok || ck "guest: sink rows == swapchain readback (3 frames)" no
awk '/^VKG guest start/{a=1;next} /^VKG rc=/{a=0} a && /^VK time wsi_frame_ms/' "$S"
cmp -s "$D/host.img" "$D/guest.img" && ck "guest image hashes == host run (20 images, byte identical)" ok || { ck "guest image hashes == host run (20 images, byte identical)" no; diff "$D/host.img" "$D/guest.img" | head -6; }
awk '/^VKG rc=/{a=1;next} /^VKG mut-rc=/{a=0} a && /^VK img/' "$S" | sort > "$D/mut.img"
if [ -s "$D/mut.img" ] && ! cmp -s "$D/mut.img" "$D/guest.img"; then ck "guest: mutant library renders different pixels (counter-proof)" ok; else ck "guest: mutant library renders different pixels (counter-proof)" no; fi
grep -aq "^VK FAIL dlopen\|^VK FAIL.*dlopen" "$S" && grep -aq "^VKG neg-missing rc=1" "$S" && ck "guest: missing .so refused (counter-proof)" ok || ck "guest: missing .so refused (counter-proof)" no
echo "VKGUEST: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
