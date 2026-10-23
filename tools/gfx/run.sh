#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gfx/run.sh -- SWR graphics stack prototype on the build host (no QEMU).
#   bash tools/gfx/run.sh          checks (tools/gfx/test.fi)
#   bash tools/gfx/run.sh bench    + measurements (tools/gfx/bench.fi), prints a table
set -uo pipefail
cd "$(dirname "$0")/../.."
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 || { echo "fetch-firnc.sh failed"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
rc=0
for p in test test_clip test_ops test_fui test_fuikind test_fuiloop $( [ "${1:-}" = bench ] && echo bench ); do
    OPT=""; [ "$p" = bench ] && OPT="--opt-level=release-fast"; FIRNLIB="$PWD/lib" vendor/firn/bin/firnc --profile=app $OPT tools/gfx/$p.fi -o "$T/$p" > "$T/$p.build" 2>&1 \
        || { echo "FAIL  build $p"; grep -v '^warning' "$T/$p.build" | head -30; rc=1; continue; }
    ARGS=()
    if [ "$p" = test_fui ]; then
        if command -v glslangValidator >/dev/null 2>&1; then
            for sh in fui_rect.vert fui_rect.frag; do glslangValidator -V "tools/gfx/shaders/$sh" -o "$T/$sh.spv" > "$T/$sh.log" 2>&1 || { echo "FAIL  glslang $sh"; head -5 "$T/$sh.log"; rc=1; }; if command -v spirv-opt >/dev/null 2>&1; then spirv-opt --inline-entry-points-exhaustive --eliminate-dead-functions --eliminate-local-multi-store "$T/$sh.spv" -o "$T/$sh.opt.spv" && mv "$T/$sh.opt.spv" "$T/$sh.spv"; fi; ARGS+=("$T/$sh.spv"); done
        else echo "SKIP  glslangValidator not installed (fui frame gate)"; fi
    fi
    if [ "$p" = test_fuikind ]; then
        if command -v glslangValidator >/dev/null 2>&1 && command -v spirv-opt >/dev/null 2>&1; then
            for k in 0 1 5 7; do bash tools/gfx/fuiconv.sh "$T/k$k" "$k" > "$T/k$k.log" 2>&1 || { echo "FAIL  fuiconv kind $k"; head -5 "$T/k$k.log"; rc=1; }; ARGS+=("$T/k$k/gpu.frag.opt.spv"); done
        else echo "SKIP  glslangValidator/spirv-opt not installed (fui kind gate)"; fi
    fi
    if [ "$p" = test_fuiloop ]; then
        if command -v glslangValidator >/dev/null 2>&1 && command -v spirv-opt >/dev/null 2>&1; then
            for k in 6 11 12 13 14 15 2 3 4 8 9 10 16; do bash tools/gfx/fuiconv.sh "$T/k$k" "$k" > "$T/k$k.log" 2>&1 || { echo "FAIL  fuiconv kind $k"; head -5 "$T/k$k.log"; rc=1; }; ARGS+=("$T/k$k/gpu.frag.opt.spv"); done
        else echo "SKIP  glslangValidator/spirv-opt not installed (fui loop kind gate)"; fi
    fi
    "$T/$p" ${ARGS[@]+"${ARGS[@]}"}; prc=$?
    [ "$prc" = 0 ] || rc=1
done
exit $rc
