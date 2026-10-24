#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
T=$(cd "$(dirname "$0")/../.." && pwd)
cd "$T" || exit 2
ok=0; bad=0
chk() { if eval "$2"; then ok=$((ok+1)); echo "  OK    $1"; else bad=$((bad+1)); echo "  FAIL  $1"; fi; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
chk "all shipped bundles pass the lint" "python3 -I tools/k15/bundle.py --lint assets/apps >/dev/null"
for miss in data/README INFO start.txt; do
  rm -rf "$W/apps"; cp -r assets/apps "$W/apps"
  rm -f "$W/apps/viewer.osp/$miss"
  chk "lint fails when a bundle lacks $miss" "! python3 -I tools/k15/bundle.py --lint $W/apps >/dev/null 2>&1"
  chk "bundle build fails early when a bundle lacks $miss" "! python3 -I tools/k15/bundle.py $W/apps $W/work >/dev/null 2>&1"
done
rm -rf "$W/apps"; cp -r assets/apps "$W/apps"
rm -f "$W/apps/viewer.osp/symbol.osym" "$W/apps/viewer.osp/symbol.txt"
chk "lint fails when a bundle has no symbol" "! python3 -I tools/k15/bundle.py --lint $W/apps >/dev/null 2>&1"
chk "every bundle build entry point calls the lint" "grep -q 'lint_all(quelle)' tools/k15/bundle.py"
echo "BUNDLELINT: $ok ok, $bad fail"
[ "$bad" = 0 ]
