#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
SHOT=${1:-}
FAIL=0
ok() { echo "  OK    $1"; }
bad() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

bash tools/readonce/run.sh || FAIL=$((FAIL + 1))

grep -q 'io.read_full(fd, target, SYM_BYTES)' kernel/user/taskbar/tblayout.fi && ok "tblayout reads the symbol file in full" || bad "tblayout.sym_of lost io.read_full"
grep -q 'fn complete' kernel/user/symvar.fi && grep -q 'fn lower_ink' kernel/user/symvar.fi && ok "symvar rejects cut-off symbols" || bad "symvar.complete/lower_ink missing"

if [ -n "$SHOT" ]; then
    if python3 -I tools/symfull/barink.py "$SHOT" > /dev/null; then
        ok "taskbar icons carry ink in the lower half"
    else
        bad "taskbar icon with empty lower half in $SHOT"
    fi
    if python3 -I tools/symfull/barink.py "$SHOT" --blank-lower > /dev/null; then
        bad "control: blanked lower halves not detected"
    else
        ok "control: icons with blanked lower half detected"
    fi
fi
exit "$FAIL"
