#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
FEED=${STORECAT_FEED:-/srv/store/osum/aktuell}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }
CHECK="python3 -I tools/storecat/check.py"

out=$($CHECK "$ROOT" tools/loader/apps.tab) && ok "apps.tab: no duplicate, base-twin or dev package" || { bad "apps.tab has bad packages"; echo "$out"; }

cp tools/loader/apps.tab "$T/dup.tab"
echo 'trash|trashbin|1.0.0|Recycle Bin|Restore deleted files|trash|fenster' >> "$T/dup.tab"
$CHECK "$ROOT" "$T/dup.tab" > "$T/dup.txt" && bad "mutant: trash next to trashbin not caught" || { grep -q 'trash runs /bin/trashbin' "$T/dup.txt" && ok "mutant: trash next to trashbin is caught" || bad "mutant: wrong message"; }

cp tools/loader/apps.tab "$T/dev.tab"
echo 'widgetdemo|widgetdemo|1.0.0|Widgets|Demo|demo|fenster' >> "$T/dev.tab"
$CHECK "$ROOT" "$T/dev.tab" > "$T/dev.txt" && bad "mutant: widgetdemo package not caught" || { grep -q 'dev profile' "$T/dev.txt" && ok "mutant: widgetdemo package is caught" || bad "mutant: wrong message"; }

if [ -f "$FEED/INDEX" ]; then
    out=$($CHECK "$ROOT" tools/loader/apps.tab "$FEED") && ok "live feed matches apps.tab, no duplicate catalog names" || { bad "live feed is stale or duplicated"; echo "$out"; }
    mkdir -p "$T/feed"; cp "$FEED/INDEX" "$T/feed/INDEX"; [ -f "$FEED/apps.tsv" ] && cp "$FEED/apps.tsv" "$T/feed/apps.tsv"
    printf 'trash\t1.0.0\t0\t1\ttrash-1.opk\tx86_64\n' >> "$T/feed/INDEX"
    $CHECK "$ROOT" tools/loader/apps.tab "$T/feed" > "$T/feed.txt" && bad "mutant: stale trash in INDEX not caught" || { grep -q 'feed package trash' "$T/feed.txt" && ok "mutant: stale trash in INDEX is caught" || bad "mutant: wrong message"; }
else
    echo "  SKIP  live feed not present ($FEED)"
fi
echo "STORECAT: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
