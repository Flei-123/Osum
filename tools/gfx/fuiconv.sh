#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gfx/fuiconv.sh <out-dir> [kind] -- builds the real fUi GPU shaders (vendor/firn/lib/fui/gpu_{vs,fs}.glsl) as Vulkan SPIR-V for the SWR lowering.
# With a kind the fragment shader is specialised (`int kind = N;`) and folded, so loop free kinds lower to straight VM code.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=$1; KIND=${2:-}
mkdir -p "$OUT"
conv() {
    sed -e 's/^#version 300 es/#version 450\nlayout(set = 0, binding = 0, std140) uniform P { vec2 u_size; vec2 u_srcsize; int u_nspot; vec4 u_spot[8]; };/' \
        -e '/^precision /d' -e '/^uniform vec2 u_size;/d' -e '/^uniform vec2 u_srcsize;/d' -e '/^uniform vec4 u_spot\[8\];/d' -e '/^uniform int u_nspot;/d' \
        -e 's/^uniform sampler2D u_atlas;/layout(set = 0, binding = 1) uniform sampler2D u_atlas;/' \
        -e 's/^uniform sampler2D u_stream;/layout(set = 0, binding = 2) uniform sampler2D u_stream;/' \
        -e 's/^uniform sampler2D u_src;/layout(set = 0, binding = 3) uniform sampler2D u_src;/' \
        -e 's/^flat \(in\|out\) vec4 v_c0;/layout(location = 0) flat \1 vec4 v_c0;/' \
        -e 's/^flat \(in\|out\) vec4 v_c1;/layout(location = 1) flat \1 vec4 v_c1;/' \
        -e 's/^flat \(in\|out\) vec4 v_g;/layout(location = 2) flat \1 vec4 v_g;/' \
        -e 's/^flat \(in\|out\) vec4 v_p;/layout(location = 3) flat \1 vec4 v_p;/' \
        -e 's/^flat \(in\|out\) vec4 v_t;/layout(location = 4) flat \1 vec4 v_t;/' \
        -e 's/^flat \(in\|out\) vec4 v_clip;/layout(location = 5) flat \1 vec4 v_clip;/' \
        -e 's/^flat \(in\|out\) vec4 v_k;/layout(location = 6) flat \1 vec4 v_k;/' \
        -e 's/^out vec4 o;/layout(location = 0) out vec4 o;/' "$1"
}
conv vendor/firn/lib/fui/gpu_vs.glsl > "$OUT/gpu.vert"
conv vendor/firn/lib/fui/gpu_fs.glsl > "$OUT/gpu.frag"
if [ -n "$KIND" ]; then sed -i "s/int kind = int(v_k.x + 0.5);/int kind = $KIND;/" "$OUT/gpu.frag"; fi
if [ "$KIND" = 6 ]; then
    perl -0pi -e 's/(for \(int k = 0; k < 4; k\+\+\) \{)\n\s*if \(k >= u_nspot\) break;(.*?\n            \}\n)(\s*\}\n)/[[unroll]] $1\n            if (k < u_nspot) {$2            }\n$3/s' "$OUT/gpu.frag"
fi
if [ "$KIND" -ge 11 ] 2>/dev/null && [ "$KIND" -le 14 ]; then
    perl -0pi -e 's/(for \(int j = -64; j <= 64; j\+\+\) \{)\n\s*if \(j < -r\) continue;\n\s*if \(j > r\) break;(.*?sum \+= src_at\(q\);\n)/[[unroll]] $1\n            if (j >= -r && j <= r) {$2            }\n/s' "$OUT/gpu.frag"
fi
if [ -n "$KIND" ]; then sed -i 's/^#version 450/#version 450\n#extension GL_EXT_control_flow_attributes : enable/' "$OUT/gpu.frag"; fi
glslangValidator -V --target-env vulkan1.0 -o "$OUT/gpu.vert.spv" "$OUT/gpu.vert" > /dev/null
glslangValidator -V --target-env vulkan1.0 -o "$OUT/gpu.frag.spv" "$OUT/gpu.frag" > /dev/null
spirv-opt --merge-return --inline-entry-points-exhaustive --eliminate-dead-functions --eliminate-local-multi-store "$OUT/gpu.vert.spv" -o "$OUT/gpu.vert.opt.spv"
OPT=(--merge-return --inline-entry-points-exhaustive --eliminate-dead-functions)
if [ -n "$KIND" ]; then OPT+=(--ccp --eliminate-dead-branches --simplify-instructions --loop-unroll -O --loop-unroll -O); else OPT+=(-O); fi
spirv-opt "${OPT[@]}" "$OUT/gpu.frag.spv" -o "$OUT/gpu.frag.opt.spv"
spirv-val "$OUT/gpu.vert.opt.spv" && spirv-val "$OUT/gpu.frag.opt.spv"
