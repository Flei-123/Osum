#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotkey/run.sh -- r1309: Ctrl+Shift+T as the scancode burst of VirtualBox (`keyboardputscancode 1d 2a 14 94 aa 9d`, no pauses).
#
#   OLDREF=<ref before the fix> bash /root/jarvis/bin/heavy bash tools/hotkey/run.sh
#
# One boot of the stick's machine (tools/design/eh6.sh, KVM, /bin/term built), drehbuch tools/hotkey/dreh.txt: tab with a focused
# terminal, both terminals closed, Ctrl+Shift+T with NO terminal (must open one, used to do nothing), tab in the new one.
# COUNTER-PROOF: the same drehbuch on OLDREF must fail at least 3 checks.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$TMPD/new" accel=kvm moreprogs=term drehbuch="$ROOT/tools/hotkey/dreh.txt" > "$TMPD/run.log" 2>&1
grep -a "FEHLGESCHLAGEN\|NICHT DA\|KEIN RECHTECK" "$TMPD/run.log" | head -5
python3 tools/hotkey/check.py "$TMPD/new" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt"); o1=$(grep -c '^  OK' "$TMPD/new.txt")
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same drehbuch on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    (cd "$OLDWT" && bash vendor/firn/fetch-firnc.sh > /dev/null 2>&1; DESIGNBUILD="$TMPD/oldbuild" bash tools/design/eh6.sh "$TMPD/old" accel=kvm moreprogs=term drehbuch="$ROOT/tools/hotkey/dreh.txt" > "$TMPD/run2.log" 2>&1)
    python3 tools/hotkey/check.py "$TMPD/old" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    [ "$f2" -ge 3 ] && echo "  OK    the old tree fails $f2 checks: they measure something" || echo "  FAIL  the old tree fails only $f2 checks"
fi
echo "== result =="
[ "$f1" -eq 0 ] && [ "$o1" -ge 7 ] && echo "  OK    all $o1 checks pass" || echo "  FAIL  $f1 failed ($o1 ok)"
[ "$f1" -eq 0 ] && [ "$o1" -ge 7 ] && { [ -z "$OLDREF" ] || [ "${f2:-0}" -ge 3 ]; }
