#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/storeui/run.sh -- the Store window on a screen, light + dark, two resolutions, with pictures.
#
#   bash tools/storeui/run.sh [outdir]      (heavy: 4 QEMU runs of tools/store/run.sh section 5)
#
# Every run is `STORE_FAST=1 STORE_RES=<WxH> STORE_MODE=<light|dark> STORE_SHOTS=<outdir> bash tools/store/run.sh`:
# the same section 5 (grid, search, detail page, install with progress, update, remove) and the PNGs
# s1-grid .. s9-end in <outdir>. tools/storeui/shotcheck.py then asserts on the pictures: the window is
# painted, the light picture is light and the dark one dark, and no run is blank.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
fail=0
for mode in light dark; do
    for res in 1024x768 1920x1080; do
        echo "== $mode $res =="
        STORE_FAST=1 STORE_RES=$res STORE_MODE=$mode STORE_SHOTS="$OUT" bash tools/store/run.sh > "$OUT/run-$mode-$res.log" 2>&1
        tail -2 "$OUT/run-$mode-$res.log" | head -1
        grep -a "FAIL" "$OUT/run-$mode-$res.log" | head -5
        grep -aq "failed" "$OUT/run-$mode-$res.log" && ! grep -aq " 0 failed" "$OUT/run-$mode-$res.log" && fail=1
    done
done
python3 -I tools/storeui/shotcheck.py "$OUT" || fail=1
echo "pictures: $OUT"
[ "$fail" = 0 ]
