#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
ROOT=$PWD
run_tree() {
    (cd "$1" && DESIGNBUILD="$TMPD/build-$2" bash tools/design/eh6.sh "$TMPD/$2" accel=kvm drehbuch="$ROOT/tools/lineedit/script.txt" > "$TMPD/$2.log" 2>&1)
    tail -2 "$TMPD/$2.log"
    if [ -n "${LINEEDIT_KEEP:-}" ]; then
        mkdir -p "$LINEEDIT_KEEP/$2"; cp "$TMPD/$2/serial.txt" "$TMPD/$2.log" "$LINEEDIT_KEEP/$2/" 2>/dev/null
        for n in "$TMPD/$2"/*.ppm; do [ -e "$n" ] && python3 tools/design/ppm2png.py "$n" "$LINEEDIT_KEEP/$2/$(basename "$n" .ppm).png" > /dev/null 2>&1; done
    fi
}
echo "== 1. line editor on this tree =="
run_tree "$ROOT" new
python3 tools/lineedit/check.py "$TMPD/new/serial.txt" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt"); o1=$(grep -c '^  OK' "$TMPD/new.txt")
f2=""
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== 2. counter-proof: the same keys on $OLDREF =="
    OLDWT="$TMPD/oldwt"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    firnenv_prepare_old_tree "$OLDWT"
    run_tree "$OLDWT" old
    python3 tools/lineedit/check.py "$TMPD/old/serial.txt" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    git worktree remove --force "$OLDWT" > /dev/null 2>&1
    [ "$f2" -ge 5 ] && echo "  OK    COUNTER-PROOF: $f2 checks red on $OLDREF" || echo "  FAIL  COUNTER-PROOF: only $f2 checks red on $OLDREF"
fi
echo "LINEEDIT: ok=$o1 fail=$f1 counter_fail=${f2:-not_run}"
[ "$f1" -eq 0 ] && [ "$o1" -ge 20 ] && { [ -z "$OLDREF" ] || [ "$f2" -ge 5 ]; }
