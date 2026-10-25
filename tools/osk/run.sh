#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
KEEP=${1:-}
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
pass=0; fail=0
for l in de en; do
    if grep -q '^osk\.title = ' locale/$l/messages; then echo "  OK    locale $l: osk.title"; pass=$((pass+1)); else echo "  FAIL  locale $l: osk.title"; fail=$((fail+1)); fi
done
if grep -q '/bin/osk' tools/usbimg/build.sh && grep -q ' osk ' tools/usbimg/build.sh; then echo "  OK    usbimg ships /bin/osk"; pass=$((pass+1)); else echo "  FAIL  usbimg list"; fail=$((fail+1)); fi
bash tools/osk/shot.sh "$D/new" > "$D/new.log" 2>&1
python3 -I tools/osk/check.py "$D/new" | tee "$D/new.res"
bash tools/osk/shot.sh "$D/bad" badscan > "$D/bad.log" 2>&1
python3 -I tools/osk/check.py "$D/bad" badscan | tee "$D/bad.res"
[ -n "$KEEP" ] && { mkdir -p "$KEEP"; cp -r "$D"/new "$D"/bad "$KEEP/" 2>/dev/null; }
n=$(cat "$D"/*.res | grep -a -c '^  FAIL')
o=$(cat "$D"/*.res | grep -a -c '^  OK')
echo "OSK: $((pass + o)) ok, $((fail + n)) fail"; [ "$n" = 0 ] && [ "$fail" = 0 ]
