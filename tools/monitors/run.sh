#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/monitors/run.sh -- gate for the multi-monitor model (L-003 r757, L-004 r758).
#
# WHAT IT MEASURES
#   1. lib/monitors/layout.fi compiles for the app AND the kernel profile.
#   2. tools/monitors/oracle.fi (host program, same lib file) answers every
#      promise with OK: arrangement, hit test, cursor clamp, window home,
#      mirror letterbox, single mode, hotplug, per-monitor scale,
#      EDID audio flag, HDA pin-sense routing.
#   3. NEGATIVE CONTROLS: the same oracle against a lib with one rule
#      broken must go red. An oracle that cannot fail measures nothing.
#   4. Facts about the test bed: QEMU's virtio-gpu has max_outputs, and the
#      kernel's vgpu driver reads the scanout count from the device.
#
# WHAT IT DOES NOT MEASURE (stated, not hidden)
#   No kernel boots here. fb.fi / wm.fi do not use the model yet
#   (see docs/MONITORS.md "What is missing"). Multi-head on screen is NOT proven.
#
# Usage: bash tools/monitors/run.sh
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

# 1. sources + compile
[ -f lib/monitors/layout.fi ] && ok "lib/monitors/layout.fi exists" || bad "layout.fi missing"
[ -f tools/monitors/oracle.fi ] && ok "oracle.fi exists" || bad "oracle.fi missing"
printf 'import monitors.layout\nfn main() -> i32 {\n    layout.reset()\n    return 0\n}\n' > "$T/k.fi"
"$FIRNC" --profile=kernel -c "$T/k.fi" -o "$T/k.o" 2> "$T/k.err" \
    && ok "lib compiles with --profile=kernel" \
    || { bad "lib does not compile with --profile=kernel"; head -5 "$T/k.err"; }
"$FIRNC" tools/monitors/oracle.fi -o "$T/oracle" 2> "$T/o.err" \
    && ok "oracle builds against lib/monitors" \
    || { bad "oracle does not build"; head -10 "$T/o.err"; }

# 2. the promises
if [ -x "$T/oracle" ]; then
    "$T/oracle" > "$T/out.txt" 2>&1
    nok=$(grep -c '^OK' "$T/out.txt")
    nbad=$(grep -c '^FAIL' "$T/out.txt")
    sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
    [ "$nbad" = 0 ] && ok "oracle: no FAIL line" || bad "oracle: $nbad FAIL lines"
    [ "$nok" -ge 70 ] && ok "oracle: $nok promises OK (>= 70)" || bad "oracle: only $nok OK (< 70)"
    pass=$((pass+nok))
fi

# 3. negative controls: break one rule at a time in a copy of the lib
mutate() { # name sed-expression
    local name=$1 expr=$2
    local L="$T/lib-$name"
    mkdir -p "$L"
    for d in lib/*; do
        [ "$(basename "$d")" = monitors ] || ln -s "$ROOT/$d" "$L/$(basename "$d")"
    done
    mkdir -p "$L/monitors"
    sed -e "$expr" lib/monitors/layout.fi > "$L/monitors/layout.fi"
    if cmp -s lib/monitors/layout.fi "$L/monitors/layout.fi"; then
        bad "control $name: the mutation did not change the file"
        return
    fi
    if ! FIRNLIB="$L" "$FIRNC" tools/monitors/oracle.fi -o "$T/o-$name" 2>/dev/null; then
        bad "control $name: mutated oracle does not build"
        return
    fi
    local nf
    nf=$("$T/o-$name" 2>&1 | grep -c '^FAIL')
    [ "$nf" -gt 0 ] && ok "control $name: oracle goes red ($nf FAIL)" \
                     || bad "control $name: oracle stays green on a broken lib"
}
mutate nooverlap 's/return ix > 0 \&\& iy > 0/return false/'
mutate nodetach  's/if is_used(k) \&\& (seen \& (1 << k)) == 0 { return E_DETACHED }/if false { return E_DETACHED }/'
mutate noeld     's/if (sense \& PS_ELD_VALID) == 0 { return 0 }//'
mutate nopresence 's/if (sense \& PS_PRESENCE) == 0 { return 0 }//'
mutate dpi       's/(w \* 2540) \/ (mm_w \* 96)/(w * 2540) \/ (mm_w * 48)/'
mutate mirrorpos 's/if g_mode == MODE_MIRROR { return 0 }//'

# 4. test-bed facts
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    qemu-system-x86_64 -device virtio-gpu-pci,help 2>&1 | grep -q 'max_outputs' \
        && ok "QEMU virtio-gpu-pci has max_outputs (two scanouts are testable)" \
        || bad "QEMU virtio-gpu-pci has no max_outputs"
fi
grep -q 'G_NUM_SCANOUTS' kernel/drv/gpu/vgpu.fi \
    && ok "vgpu.fi reads num_scanouts from the device config" \
    || bad "vgpu.fi no longer reads num_scanouts"
grep -q 'fn set_scanout' kernel/drv/gpu/vgpu.fi \
    && ok "vgpu.fi has SET_SCANOUT (one scanout; per-output is the open step)" \
    || bad "vgpu.fi lost set_scanout"

echo "monitors: $pass promises, $fail errors"
[ "$fail" = 0 ]
