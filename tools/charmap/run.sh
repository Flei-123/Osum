#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/charmap/run.sh -- P-015 character map (/bin/charmap): blocks, search (code point / block / character), a click copies the
# character to the clipboard, glyphs the font lacks are marked. Witness for "the font has it" is the cmap of the font FILE, not the app.
# Boot 1: the real program. Boot 2 (COUNTER-PROOF): `charmap nocheck` (every code point "present") must be caught by the witness.
#   /root/jarvis/bin/heavy bash tools/charmap/run.sh [<keep-dir>]
set -uo pipefail
cd "$(dirname "$0")/../.."
KEEP=${1:-}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
# static: locale keys in both languages, bundle in the image list
for l in de en; do
    n=$(grep -c '^charmap\.\(title\|search\|only\|prev\|next\|jump\|copied\|missing\|nomatch\|empty\|page\|info\) = ' locale/$l/messages)
    if [ "$n" = 12 ]; then echo "  OK    locale $l: 12 charmap.* keys"; pass=$((pass+1)); else echo "  FAIL  locale $l: $n of 12 charmap.* keys"; fail=$((fail+1)); fi
done
if grep -q '/apps/charmap.osp/start' tools/usbimg/build.sh && grep -q '/bin/charmap' tools/usbimg/build.sh; then echo "  OK    usbimg ships /bin/charmap and its bundle"; pass=$((pass+1)); else echo "  FAIL  usbimg list"; fail=$((fail+1)); fi
bash tools/charmap/shot.sh "$D/new" > "$D/new.log" 2>&1
python3 -I tools/charmap/check.py "$D/new" | tee "$D/new.res"
bash tools/charmap/shot.sh "$D/nocheck" nocheck > "$D/nc.log" 2>&1
python3 -I tools/charmap/check.py "$D/nocheck" nocheck | tee "$D/nc.res"
python3 -I tools/charmap/check.py "$D/new" new "$D/nocheck" | grep -a "nocheck run" | tee "$D/cmp.res"
[ -n "$KEEP" ] && { mkdir -p "$KEEP"; cp -r "$D"/new "$D"/nocheck "$KEEP/" 2>/dev/null; }
cat "$D"/*.res | grep -a -c '^  FAIL' | { read n; echo "CHARMAP: $((pass + $(grep -ac '^  OK' "$D"/*.res | awk -F: '{s+=$2} END{print s}'))) ok, $((fail + n)) fail"; [ "$n" = 0 ] && [ "$fail" = 0 ]; }
