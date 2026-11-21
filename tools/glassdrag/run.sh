#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
WT=""
cleanup() {
    [ -n "$WT" ] && git worktree remove --force "$WT" > /dev/null 2>&1
    rm -rf "$OUT"
}
trap cleanup EXIT
ROOT=$(pwd)
if [ "${GLASSDRAG_MUTANT:-0}" = 1 ]; then
    WT=$(mktemp -d)
    git worktree add --detach "$WT" HEAD > /dev/null 2>&1 || { echo "FAIL  no worktree"; exit 1; }
    sed -i '/^                wmlayout.ss(state, wmlayout.S_GLASSGEN/d' "$WT/kernel/ui/wm/wmbase.fi"
    ROOT=$WT
fi
cd "$ROOT"
export DESIGNBUILD="$OUT/build"
bash tools/design/audit.sh "$OUT/run" accel=kvm uitrace=yes halt=200 \
    drehbuch="$ROOT/tools/glassdrag/drag.txt" > "$OUT/log" 2>&1
for n in g-01 g-02 g-03 g-04; do
    [ -s "$OUT/run/$n.ppm" ] || { echo "  FAIL  no screenshot $n"; tail -5 "$OUT/log"; exit 1; }
done
grep -a "^wm: frame n=" "$OUT/run/serial.txt" | tail -1
python3 -I "$ROOT/tools/glassdrag/check.py" "$OUT/run"
