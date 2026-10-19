#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/themeboot/run.sh -- r1123: a program whose first read of /etc/theme.conf fails must keep the mode the file says (light OR dark)
# (old behaviour: keys from read 1, the compare-copy from a second read at the end of the reload -> read 1 failed = dark start,
# the copy held the GOOD bytes, so the poll never sees a change = dark for good ("1 boot in 6 comes up dark").
# MEASURED (r1171, debug lines in the old tree): a failed key read leaves set_mode = sch_mode = DARK (NOT AUTO, so the result
# does not depend on the clock), and the old taskbar/desktop reload TWICE at boot -- one failing key read heals itself with the
# second reload. The counter-probe therefore fails the first TWO key reads (flaky=2, key reads only; the copy read stays good).
# The file mode is always light: the new tree must show the dark tile OFF (an=0), the counter-probe tree dark (an=1).
# Hook: image option flaky=K (/etc/themeflaky) makes the first K reads of /etc/theme.conf per program fail, deterministic.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
BASE=${THEMEBOOT_BASE:-$(git log --format=%H --grep='^wlibc: theme.conf is read once' -1 | xargs -r -I{} git rev-parse {}^)}
cleanup() { [ -n "${OLD:-}" ] && git worktree remove --force "$OLD" >/dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "THEMEBOOT: skipped, no qemu"; exit 0; }
cat > "$TMPD/plan.txt" <<'PLAN'
marke ---- Kontrollzentrum ----
ziel qsfeld
warte 2
foto q01_offen
PLAN

FILE_MODE=light; WANT=0; OLD_AN=1
echo "file mode=$FILE_MODE: correct tile an=$WANT, the old tree (failed key reads) starts dark an=$OLD_AN"
tile() { grep -a 'qs: kachel n=3 ' "$1/serial.txt" 2>/dev/null | head -1; }

echo "== 1. new tree, first read of /etc/theme.conf fails =="
bash tools/toolbench/build.sh "$TMPD/new" desk=yes mode=$FILE_MODE wait=12 last=300 flaky=1 extra="wighalt=120" plan="$TMPD/plan.txt" > "$TMPD/new.log" 2>&1
T=$(tile "$TMPD/new")
[ -n "$T" ] && ok "the new tree reports the dark tile ($T)" || bad "no 'qs: kachel n=3' line in the new tree boot"
echo "$T" | grep -qa "an=$WANT" && ok "mode=$FILE_MODE holds although the first read failed (tile an=$WANT)" || bad "new tree started dark: $T"

echo "== 2. counter-probe: tree before the fix + the same hook =="
if [ -z "$BASE" ]; then bad "no base commit for the counter-probe"; else
    OLD="$TMPD/old"
    git worktree add --detach "$OLD" "$BASE" > "$TMPD/wt.log" 2>&1 || bad "worktree for the counter-probe failed: $(tail -2 "$TMPD/wt.log")"
    if [ -d "$OLD" ]; then
        python3 tools/themeboot/oldhook.py "$ROOT/kernel/user/wlibc.fi" "$OLD/kernel/user/wlibc.fi" > "$TMPD/hook.log" 2>&1 \
            || bad "hook patch failed: $(tail -2 "$TMPD/hook.log")"
        cp tools/toolbench/build.sh "$OLD/tools/toolbench/build.sh"
        ( cd "$OLD" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
          bash tools/toolbench/build.sh "$TMPD/oldout" desk=yes mode=$FILE_MODE wait=12 last=300 flaky=2 extra="wighalt=120" plan="$TMPD/plan.txt" ) > "$TMPD/old.log" 2>&1
        T2=$(tile "$TMPD/oldout")
        [ -n "$T2" ] && echo "$T2" | grep -qa "an=$OLD_AN" && ok "the old way starts dark (an=$OLD_AN, wrong for mode=$FILE_MODE) with the same failing read ($T2)" || bad "counter-probe did not show the bug: '$T2'"
    fi
fi
echo "== THEMEBOOT: $pass green, $fail red =="
[ "$fail" -eq 0 ]
