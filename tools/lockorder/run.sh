#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
python3 -I tools/lockorder/lockorder.py kernel L_FD L_WLQ > "${TMPDIR:-/tmp}/lockorder.$$" ; rc=$?
grep -E "LEAF|CYCLE" "${TMPDIR:-/tmp}/lockorder.$$"
rm -f "${TMPDIR:-/tmp}/lockorder.$$"
[ $rc -eq 0 ] && echo "lockorder: L_FD and L_WLQ are leaf locks" || echo "lockorder: FAIL"
exit $rc
