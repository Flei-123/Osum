#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vboxlag/vis.sh -- visual gate of the diff flush: the same pointer series with the diff flush and with `nodiff` must give
# pixel-identical screendumps (time-dependent areas masked, tools/vboxlag/compare.py). Optional third run with `fbstreifen`.
#
#   IMG=<personal image> [OUT=<dir>] [STRIPE=1] bash tools/vboxlag/vis.sh      (start through /root/jarvis/bin/heavy)
set -uo pipefail
cd "$(dirname "$0")/../.."
IMG=${IMG:?set IMG=<personal image>}
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
run() {  # name extra-words
    for _ in 1 2 3; do
        rm -rf "$OUT/$1"
        RES=${RES:-1280x800} IMG="$IMG" OUT="$OUT/$1" EXTRA="$2" bash tools/vboxlag/visual.sh > "$OUT/$1.log" 2>&1
        grep -q "login=1" "$OUT/$1.log" && return 0
    done
    return 1
}
run diff "" || { echo "FAIL diff run: no login"; exit 1; }
run nodiff "nodiff" || { echo "FAIL nodiff run: no login"; exit 1; }
python3 -I tools/vboxlag/compare.py "$OUT/diff" "$OUT/nodiff" "$OUT/cmp"; rc=$?
if [ "${STRIPE:-0}" = 1 ]; then
    run stripe "fbstreifen" || { echo "FAIL stripe run: no login"; exit 1; }
    python3 -I tools/vboxlag/compare.py "$OUT/stripe" "$OUT/nodiff" "$OUT/cmp-stripe" || rc=1
fi
[ $rc -eq 0 ] && echo "VERDICT vis OK" || echo "VERDICT vis FAIL"
exit $rc
