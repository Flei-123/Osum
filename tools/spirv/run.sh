#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/spirv/run.sh -- SPIR-V parser / validator / SWR lowering (lib/spirv): host checks, glslang + spirv-val cross-check, fuzz.
#   needs glslangValidator (+ spirv-val for the cross-check); without them only the hand-assembled module is tested.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0
FIRNLIB="$PWD/lib" "$FIRNC" --profile=app tools/spirv/test.fi -o "$T/test" > "$T/build" 2>&1 \
    || { echo "FAIL  build test"; grep -v '^warning\|^ld:' "$T/build" | head -30; exit 1; }
files=()
if command -v glslangValidator >/dev/null 2>&1; then
    for s in tools/spirv/shaders/*.frag; do
        b=$(basename "$s" .frag)
        if glslangValidator -V "$s" -o "$T/$b.spv" > "$T/$b.log" 2>&1; then
            files+=("$T/$b.spv")
            if [ "$b" = ok_loop ] && command -v spirv-opt >/dev/null 2>&1; then
                spirv-opt --merge-return --inline-entry-points-exhaustive --eliminate-dead-functions --eliminate-local-multi-store --eliminate-local-single-block --eliminate-local-single-store --simplify-instructions --ssa-rewrite --eliminate-dead-code-aggressive --eliminate-dead-branches --merge-blocks "$T/$b.spv" -o "$T/ok_loop_ssa.spv" && files+=("$T/ok_loop_ssa.spv")
            fi
            if command -v spirv-val >/dev/null 2>&1; then
                spirv-val --target-env vulkan1.0 "$T/$b.spv" > "$T/$b.val" 2>&1 && echo "OK    spirv-val accepts $b" || { echo "FAIL  spirv-val rejects $b (generator problem)"; rc=1; }
            fi
        else echo "FAIL  glslang $b"; head -5 "$T/$b.log"; rc=1; fi
    done
else echo "SKIP  glslangValidator not installed (hand-assembled module only)"; fi
"$T/test" "${files[@]}" || rc=1
exit $rc
