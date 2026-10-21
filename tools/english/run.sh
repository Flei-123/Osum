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
. "${FIRN:-/root/firn}/tools/testkit/testkit.sh"

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
base=$(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD main 2>/dev/null || true)
if [ -z "$base" ] || [ "$base" = "$(git rev-parse HEAD)" ]; then
    ok "nothing added since main (merge base = HEAD)"
else
    out=$(python3 tools/english/count.py --diff "$base" 2>&1); rc=$?
    printf '%s\n' "$out" | sed 's/^/        /' | head -40
    [ $rc -eq 0 ] && ok "new lines are English" || bad "German in new lines"
fi
echo "== 4. planted German in a scratch repo is caught by --diff =="
plant=$(mktemp -d)
trap 'rm -rf "$plant"' EXIT
mkdir -p "$plant/tools" "$plant/kernel"
cp -r tools/english "$plant/tools/english"
rm -rf "$plant/tools/english/__pycache__"
printf '%s\n' 'fn set_width(x: u64) -> u64 {' '    return x' '}' > "$plant/kernel/probe.fi"
( cd "$plant" && git init -q . && git add -A && git commit -q -m base ) >/dev/null 2>&1
printf '%s\n' 'fn breite_setzen(x: u64) -> u64 {' '    // das ist nicht gut, weil die Zeile fehlt' '    return x' '}' >> "$plant/kernel/probe.fi"
out=$(cd "$plant" && python3 -I tools/english/count.py --diff HEAD 2>&1); rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "new German name" && echo "$out" | grep -q "comment" \
    && ok "a planted German name and comment line are rejected" || bad "planted German not caught: $out"
( cd "$plant" && git checkout -q -- kernel/probe.fi ) >/dev/null 2>&1
printf '%s\n' 'fn set_height(x: u64) -> u64 {' '    // this is fine because the row is there' '    return x' '}' >> "$plant/kernel/probe.fi"
out=$(cd "$plant" && python3 -I tools/english/count.py --diff HEAD 2>&1); rc=$?
[ $rc -eq 0 ] && ok "English lines pass" || bad "English lines rejected: $out"
echo "ENGLISH: $pass passed, $fail failed"
[ $fail -eq 0 ]
