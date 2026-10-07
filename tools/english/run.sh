#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/english/run.sh -- THE ENGLISH GUARD (Justin, 07.10.2026: code is English, German lives in the catalogs).
#
#   bash tools/english/run.sh
#
# 1. the counter works (a German identifier, comment and log text ARE counted -- the counter-proof)
# 2. no file got MORE German than in tools/english/baseline.json (a new file starts at zero)
# 3. the lines added since the merge base with main are English (the "new code only English" rule)
set -uo pipefail
cd "$(dirname "$0")/../.."
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

echo "== 1. the counter counts =="
python3 - <<'PY' && ok "German identifier, comment line and log text are counted; English is not" || bad "the counter does not count"
import sys
sys.path.insert(0, "tools/english")
import count
i, c, l = count.scan_fi('fn breite_setzen(x: u64) {\n    // das ist nicht gut, weil die Zeile fehlt\n    say("der Wert ist nicht gesetzt")\n}\n')
assert i >= 1 and c == 1 and l == 1, (i, c, l)
i, c, l = count.scan_fi('fn set_width(x: u64) {\n    // this is fine because the row is there\n    say("the value is not set")\n}\n')
assert (i, c, l) == (0, 0, 0), (i, c, l)
PY

echo "== 2. no file got more German =="
out=$(python3 tools/english/count.py --check 2>&1); rc=$?
printf '%s\n' "$out" | sed 's/^/        /' | head -30
[ $rc -eq 0 ] && ok "the German in the tree did not grow" || bad "the German in the tree grew"

echo "== 3. the lines added since the merge base are English =="
base=$(git merge-base HEAD main 2>/dev/null || true)
if [ -z "$base" ] || [ "$base" = "$(git rev-parse HEAD)" ]; then
    ok "nothing added since main (merge base = HEAD)"
else
    out=$(python3 tools/english/count.py --diff "$base" 2>&1); rc=$?
    printf '%s\n' "$out" | sed 's/^/        /' | head -40
    [ $rc -eq 0 ] && ok "new lines are English" || bad "German in new lines"
fi
echo "ENGLISH: $pass passed, $fail failed"
[ $fail -eq 0 ]
