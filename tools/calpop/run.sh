#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/calpop/run.sh -- P-011 calendar popup on the clock: open, month grid (Monday first), next/prev, pick, today,
# toggle / Esc / outside press close it. Counter-proof: on the tree before calpop.fi the same drehbuch reports no
# `calpop: open` and every check below goes red.
#   /root/jarvis/bin/heavy bash tools/calpop/run.sh [<keep-dir>]
set -uo pipefail
cd "$(dirname "$0")/../.."
KEEP=${1:-}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
bash tools/calpop/shot.sh "$D/new" > "$D/new.log" 2>&1
python3 -I tools/calpop/check.py "$D/new" | tee "$D/new.res"
[ -n "$KEEP" ] && { mkdir -p "$KEEP"; cp "$D"/new/* "$KEEP/" 2>/dev/null; }
grep -q 'RESULT ok=[0-9]* fail=0' "$D/new.res"
