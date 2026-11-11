#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vulkan/run.sh -- libvulkan.so.1 (Firn, lib/vulkan) against lavapipe: same C client, byte-identical readbacks, mutation counter-proofs.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
LVP=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
. tools/lib/tmpdir.sh; osum_tmp_guard "${1:-}" "$D"
pass=0; fail=0
ck() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
python3 -I tools/vulkan/genproc.py "$PWD" > /dev/null
git diff --quiet -- lib/vulkan/vkproc.fi && ck "vkproc.fi is generated from the exports (no drift)" ok || ck "vkproc.fi is generated from the exports (no drift)" no
gcc -O1 -Wall -o "$D/client" tools/vulkan/client.c -ldl && ck "client builds" ok || { ck "client builds" no; exit 1; }
FIRNLIB="$PWD/lib" $FIRNC --shared -o "$D/libvulkan.so.1" lib/vulkan/libvulkan.fi > "$D/build.log" 2>&1 && ck "firnc --shared builds libvulkan.so.1" ok || { ck "firnc --shared builds libvulkan.so.1" no; grep -v '^warning' "$D/build.log" | head -20; exit 1; }
n=$(nm -D "$D/libvulkan.so.1" | grep -c ' T vk')
[ "$n" -ge 80 ] && ck "at least 80 vk* symbols exported ($n)" ok || ck "at least 80 vk* symbols exported ($n)" no
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
mutate "no rounding" vkres.fi 's/v \* 255.0f + 0.5f/v * 255.0f/'
mutate "no BGRA swizzle" vkexec.fi 's/if format == 44 as u32 { return b/if format == 99 as u32 { return b/'
mutate "ignored row length" vkexec.fi 's/if rowlen == 0 as u64 { rowlen = w }/rowlen = w/'
mutate "wrong copy offset" vkexec.fi 's/rt.mem_copy(dp + d_o, sp + so, n as usize)/rt.mem_copy(dp + d_o, sp, n as usize)/'
mutate "fill skipped" vkexec.fi 's/if op == vkcmd.OP_FILL { exec_fill(rec) }//'
gcc -O1 -Wall -o "$D/draw" tools/vulkan/draw.c -ldl && ck "draw client builds" ok || { ck "draw client builds" no; exit 1; }
mkdir -p "$D/spv" "$D/lvpd" "$D/oursd"
for sh in tools/vulkan/shaders/tri.vert tools/vulkan/shaders/tri.frag tools/vulkan/shaders/push.frag tools/vulkan/shaders/depth.vert tools/vulkan/shaders/quad.vert tools/vulkan/shaders/quad.frag tools/vulkan/shaders/inst.vert tools/vulkan/shaders/inst.frag tools/vulkan/shaders/ubo.vert tools/vulkan/shaders/ubo.frag tools/gfx/shaders/fui_rect.vert tools/gfx/shaders/fui_rect.frag; do
    b=$(basename "$sh")
    glslangValidator -V "$sh" -o "$D/spv/$b.spv" > /dev/null 2>&1 && spirv-opt --inline-entry-points-exhaustive --eliminate-dead-functions --eliminate-local-multi-store "$D/spv/$b.spv" -o "$D/spv/$b.opt" || ck "shader $b compiles" no
done
CASES="tri tri_bgra tri_view push quad depth fui cull cullfront dops dnowrite stencil quad_bgra quad_npot inst many dubo area rpass blit"
WSI_CASES="wsi wsi1 wsi2"
VK_DRIVER_FILES=$LVP timeout 120 "$D/draw" libvulkan.so.1 1 "$D/lvpd" "$D/spv" > "$D/draw_lvp.txt" 2>&1
grep -q "^VK DONE bad=0" "$D/draw_lvp.txt" && ck "draw client: lavapipe reference passes" ok || ck "draw client: lavapipe reference passes" no
timeout 120 stdbuf -o0 "$D/draw" "$D/libvulkan.so.1" 0 "$D/oursd" "$D/spv" > "$D/draw_ours.txt" 2>&1
grep -q "^VK DONE bad=0" "$D/draw_ours.txt" && ck "draw client: OrientOS ICD passes (18 scenes)" ok || { ck "draw client: OrientOS ICD passes (18 scenes)" no; grep FAIL "$D/draw_ours.txt" | head; }
draw_match() {
    local dir=$1 c r=0
    for c in $CASES; do
        python3 -I tools/vulkan/cmp.py "$D/lvpd/$c.rgba" "$dir/$c.rgba" 0.5 4 > "$dir/$c.cmp" 2>&1 || r=1
    done
    return $r
}
for c in $CASES; do
    python3 -I tools/vulkan/cmp.py "$D/lvpd/$c.rgba" "$D/oursd/$c.rgba" 0.5 4 > "$D/oursd/$c.cmp" 2>&1 && ck "draw $c == lavapipe ($(cat "$D/oursd/$c.cmp"))" ok || ck "draw $c == lavapipe ($(cat "$D/oursd/$c.cmp"))" no
done
for c in $WSI_CASES; do
    python3 -I tools/vulkan/cmp.py "$D/lvpd/fui.rgba" "$D/oursd/$c.rgba" 0.5 4 > "$D/oursd/$c.cmp" 2>&1 && ck "swapchain frame $c == lavapipe fui ($(cat "$D/oursd/$c.cmp"))" ok || ck "swapchain frame $c == lavapipe fui ($(cat "$D/oursd/$c.cmp"))" no
done
[ "$(grep -c '^VK ok sink rows' "$D/draw_ours.txt")" -eq 3 ] && ck "present sink rows == swapchain readback (3 frames, strided)" ok || ck "present sink rows == swapchain readback (3 frames, strided)" no
[ "$(grep -c '^VK ok acquire cycles' "$D/draw_ours.txt")" -eq 1 ] && [ "$(grep -c '^VK ok present counter' "$D/draw_ours.txt")" -eq 1 ] && ck "acquire cycles 3 images, present counter 3" ok || ck "acquire cycles 3 images, present counter 3" no
[ "$(grep '^VK img wsi' "$D/draw_ours.txt" | awk '{print $4}' | sort -u | wc -l)" -eq 1 ] && ck "3 swapchain images render identical pixels" ok || ck "3 swapchain images render identical pixels" no
[ "$(grep '^VK img wsi$\|^VK img wsi ' "$D/draw_ours.txt" | awk '{print $4}')" = "$(grep '^VK img fui ' "$D/draw_ours.txt" | awk '{print $4}')" ] && ck "swapchain frame hash == offscreen fui hash (byte identical)" ok || ck "swapchain frame hash == offscreen fui hash (byte identical)" no
grep '^VK time wsi_frame_ms' "$D/draw_ours.txt"
mutate_wsi() {
    local name=$1 file=$2 expr=$3 pat=$4
    rm -rf "$D/m"; mkdir -p "$D/m/out"; cp -r lib "$D/m/lib"
    sed -i "$expr" "$D/m/lib/vulkan/$file"
    if cmp -s "lib/vulkan/$file" "$D/m/lib/vulkan/$file"; then ck "wsi counter-proof $name: mutation applied" no; return; fi
    FIRNLIB="$D/m/lib" $FIRNC --shared -o "$D/m/libvulkan.so.1" "$D/m/lib/vulkan/libvulkan.fi" > "$D/m/build.log" 2>&1 || { ck "wsi counter-proof $name: mutant builds" no; return; }
    timeout 120 stdbuf -o0 "$D/draw" "$D/m/libvulkan.so.1" 0 "$D/m/out" "$D/spv" > "$D/m/out.txt" 2>&1
    if grep -q "^VK FAIL $pat" "$D/m/out.txt"; then ck "wsi counter-proof $name: client reports FAIL $pat" ok; else ck "wsi counter-proof $name: mutant must fail $pat" no; fi
}
mutate_wsi "sink stride ignored" vkwsi.fi 's/let d: u64 = dst + y \* stride/let d: u64 = dst + y * w * 4 as u64/' "sink rows"
mutate_wsi "present skips sink" vkwsi.fi 's/if dst == 0 as u64 { return }/return/' "sink rows"
mutate_wsi "acquire does not advance" vkwsi.fi 's/(i + 1 as u64) % n)/i)/' "acquire cycles"
mutate_wsi "present counter dropped" vkwsi.fi 's/S_PRESENTS) + 1 as u64)/S_PRESENTS))/' "present counter"
mutate_draw() {
    local name=$1 file=$2 expr=$3
    rm -rf "$D/m"; mkdir -p "$D/m/out"; cp -r lib "$D/m/lib"
    sed -i "$expr" "$D/m/lib/vulkan/$file"
    if cmp -s "lib/vulkan/$file" "$D/m/lib/vulkan/$file"; then ck "draw counter-proof $name: mutation applied" no; return; fi
    FIRNLIB="$D/m/lib" $FIRNC --shared -o "$D/m/libvulkan.so.1" "$D/m/lib/vulkan/libvulkan.fi" > "$D/m/build.log" 2>&1 || { ck "draw counter-proof $name: mutant builds" no; return; }
    timeout 120 stdbuf -o0 "$D/draw" "$D/m/libvulkan.so.1" 0 "$D/m/out" "$D/spv" > "$D/m/out.txt" 2>&1
    if draw_match "$D/m/out"; then ck "draw counter-proof $name: mutant must differ from lavapipe" no; else ck "draw counter-proof $name: mutant differs from lavapipe" ok; fi
}
mutate_draw "render pass load op dropped" vkpass.fi 's/rt.st64(r, 4, (rt.ld64(ptab, cidx as usize) >> 32 as u64) \& 0xFF as u64)/rt.st64(r, 4, 0 as u64)/'
mutate_draw "clear attachments ignored" vkrender.fi 's/fill_rect32((\*f).color, (\*f).w, (\*f).h, area, px)//'
mutate_draw "blit flip ignored" vkblit.fi 's/if dx1 < dx0 { tx = dx0 - 1 as i64 - x }//'
mutate_draw "no viewport y flip" vkrender.fi 's/0.0f - y \* sy + w \* oy/y * sy + w * oy/'
mutate_draw "push constants dropped" vkrender.fi 's/rt.mem_copy(ubo + (lower.PUSH_BASE as u64), rs + (R_PUSH as u64) \* 8 as u64, PUSH_WORDS \* 8)//'
mutate_draw "blend ignored" vkrender.fi 's/raster.frame_set_blend(f, (flags \& vkpipe.F_BLEND) != 0 as u64)/raster.frame_set_blend(f, false)/'
mutate_draw "depth test ignored" vkrender.fi 's/(\*f).depth_test = (flags \& vkpipe.F_DEPTH) != 0 as u64 \&\& /(*f).depth_test = false \&\& /'
mutate_draw "command buffer capped at 2048 commands" vkcmd.fi 's/const CMD_LIMIT: usize = 1048576/const CMD_LIMIT: usize = 2048/'
mutate_draw "BGRA swizzle skipped" vkrender.fi 's/if rt.ld64(rs, R_BGRA) != 0 as u64 { swap_rb/if rt.ld64(rs, R_BGRA) == 99 as u64 { swap_rb/'
mutate_draw "index buffer offset ignored" vkrender.fi 's/rt.ld8(p + ioff + idx/rt.ld8(p + idx/g'
mutate_draw "vertex attribute offset ignored" vkrender.fi 's/ + vn \* rt.ld64(p, vkpipe.P_STRIDE0 + binding) + off$/ + vn * rt.ld64(p, vkpipe.P_STRIDE0 + binding)/'
mutate_draw "texture slot shifted" vkrender.fi 's/raster.frame_set_texture_slot(f, b, tp, tw, th)/raster.frame_set_texture_slot(f, b + 1, tp, tw, th)/'
mutate_draw "scissor ignored" vkrender.fi 's/raster.frame_set_scissor(f, x0, y0, x1, y1)/raster.frame_set_scissor(f, 0, 0, (*f).w, (*f).h)/'
mutate_draw "viewport ignored" vkrender.fi 's/if rt.ld64(rs, R_HASVP) != 0 as u64 {/if rt.ld64(rs, R_HASVP) == 99 as u64 {/'
mutate_draw "uniform buffer offset ignored" vkrender.fi 's/rt.mem_copy(ubo, p + off, n as usize)/rt.mem_copy(ubo, p, n as usize)/'
mutate_draw "cull ignored" vkrender.fi 's/(\*f).cull = (cull_mode \& pos_bit) != 0 as u64/(*f).cull = false/;s/(\*f).cull_neg = (cull_mode \& neg_bit) != 0 as u64/(*f).cull_neg = false/'
mutate_draw "front face ignored" vkrender.fi 's/let front_pos: bool = ((rastw >> 8 as u64) \& 255 as u64) == 1 as u64/let front_pos: bool = false/'
mutate_draw "depth write ignored" vkrender.fi 's/(\*f).depth_write = ((dop >> 8 as u64) \& 1 as u64) != 0 as u64/(*f).depth_write = true/'
mutate_draw "depth compare op ignored" vkrender.fi 's/(\*f).depth_func = (dop \& 255 as u64) as i32/(*f).depth_func = 1/'
mutate_draw "stencil ignored" vkrender.fi 's/(\*f).stp = rs + (R_STSTATE as u64) \* 8 as u64/(*f).stp = 0 as u64/'
mutate_draw "render area clear ignored" vkrender.fi 's/fill_rect32(color, w, h, area, px)/fill_rect32(color, w, h, 0 as u64, px)/'
mutate_draw "dynamic uniform offset ignored" vkrender.fi 's/let off: u64 = rt.ld64(s, 2) + rt.ld64(rs, R_DOFF)/let off: u64 = rt.ld64(s, 2)/'
mutate_draw "first instance ignored" vkrender.fi 's/run_batch(rs, f, p, indexed, first, voff, first_inst + inst, t0, nt)/run_batch(rs, f, p, indexed, first, voff, inst, t0, nt)/'
mutate_draw "instance rate ignored" vkrender.fi 's/!= 0 as u64 { vn = inst }/== 99 as u64 { vn = inst }/'
mutate_draw "BGRA texture swizzle skipped" vkrender.fi 's/swap_rb(tp, (tw as u64) \* (th as u64))//'
mutate_draw "non-power-of-two wrap" ../gpu/swr/pixel.fi 's/if (n \& (n - 1)) == 0 { return i \& (n - 1) }/return i \& (n - 1)/'
echo "VULKAN: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
