#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/odbc/run.sh -- gate for the ODB host client (docs/ODB.md, tools/odbc). Host only, no OS needed:
# frame codec + resync fuzz, TLV, session/auth/flow-control against the Python mock agent, CLI end to end.
set -uo pipefail
cd "$(dirname "$0")"
LOG=$(mktemp); trap 'rm -f "$LOG"' EXIT
python3 -I -W ignore -m unittest discover -s . -p 'test_*.py' -v > "$LOG" 2>&1
rc=$?
ok=$(grep -c ' \.\.\. ok$' "$LOG"); bad=$(grep -cE ' \.\.\. (FAIL|ERROR)$' "$LOG")
grep -E ' \.\.\. (FAIL|ERROR)$' "$LOG" | sed 's/^/  FAIL /'
[ "$rc" -ne 0 ] && tail -30 "$LOG"
echo "odbc unit tests: $ok OK / $bad FAIL"
exit $rc
