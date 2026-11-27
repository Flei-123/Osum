#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
OLD_REF=${OLD_REF:-88c308856}
T=$(mktemp -d)
trap 'git worktree remove --force "$T/old" >/dev/null 2>&1; rm -rf "$T" "$T-build" "$T-oldbuild"' EXIT
SCRIPT="$ROOT/tools/design/explorer.txt"
DESIGNBUILD="$T-build" bash tools/design/audit.sh "$T/live" accel=kvm uitrace=yes halt=300 mode=dark res=1280x800 drehbuch="$SCRIPT" > "$T/live.log" 2>&1
echo "== live =="
python3 -I tools/explorerwin11/check.py "$T/live" | tee "$T/live.txt"
live_fail=$(grep -c '^  FAIL' "$T/live.txt")
echo "== counter-proof: tree before the Windows 11 layout =="
git worktree add --detach "$T/old" "$OLD_REF" > "$T/wt.log" 2>&1 || { cat "$T/wt.log"; exit 1; }
(cd "$T/old" && DESIGNBUILD="$T-oldbuild" bash tools/design/audit.sh "$T/prev" accel=kvm uitrace=yes halt=300 mode=dark res=1280x800 drehbuch="$SCRIPT" > "$T/prev.log" 2>&1)
python3 -I tools/explorerwin11/check.py "$T/prev" | tee "$T/prev.txt"
prev_fail=$(grep -c '^  FAIL' "$T/prev.txt")
echo "== result =="
[ "$live_fail" -eq 0 ] && echo "  OK    Windows 11 layout: places only, flat buttons, address field" || echo "  FAIL  layout checks failed ($live_fail)"
[ "$prev_fail" -ge 3 ] && echo "  OK    counter-proof: old tree fails $prev_fail checks" || echo "  FAIL  counter-proof: old tree fails only $prev_fail checks"
[ "$live_fail" -eq 0 ] && [ "$prev_fail" -ge 3 ]
