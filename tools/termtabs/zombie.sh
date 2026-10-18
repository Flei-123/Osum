#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/zombie.sh -- r1014 follow-up (W-X2): opening and closing terminal tabs leaves no corpse, no task and no window behind.
#
#   [OLDREF=<ref>] [CYC=30] bash /root/jarvis/bin/heavy bash tools/termtabs/zombie.sh
#
# One boot of the stick's machine (tools/design/eh6.sh, KVM, /bin/term built). The drehbuch takes a `ps` listing, opens a tab
# (Ctrl+Shift+T), in every second one starts `sleep 1000`, and closes it (Ctrl+Shift+W) CYC times (default 30 -- more than the task table has free slots), then takes a second
# `ps`. tools/termtabs/zombie.py compares: every tab was made and closed, no `tab shell started: 0`, no corpse, task count back at the start.
# COUNTER-PROOF (OLDREF): the same drehbuch on a tree without the fix must fail.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
CYC=${CYC:-30}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
{
    echo "warteauf 'launcher: ready' || 120"
    echo "warte 8"
    echo "klick 300,600"
    echo "warte 1"
    echo "tippe ps"
    echo "taste ret"
    echo "warte 4"
    for i in $(seq 1 "$CYC"); do
        echo "marke tt: new win="
        echo "taste ctrl-shift-t"
        echo "warteneu tt: new win= || 40"
        echo "warte 2"
        # every second tab closes with a foreground program running (the shell is not reading: it cannot see the end of its input)
        if [ $((i % 2)) -eq 0 ]; then
            echo "tippe sleep 1000"
            echo "taste ret"
            echo "warte 2"
        fi
        echo "marke tt: close win="
        echo "taste ctrl-shift-w"
        echo "warteneu tt: close win= || 20"
        echo "warte 2"
    done
    echo "klick 300,600"
    echo "warte 1"
    echo "tippe ps"
    echo "taste ret"
    echo "warte 6"
    echo "foto z-end"
} > "$TMPD/dreh.txt"
run() { # run <outdir> <worktree> <log>
    (cd "$2" && DESIGNBUILD="$TMPD/build-$1" bash tools/design/eh6.sh "$TMPD/$1" accel=kvm moreprogs=term drehbuch="$TMPD/dreh.txt" > "$TMPD/$1.log" 2>&1)
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$1.log" | head -3
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP/$1"; cp "$TMPD/$1/serial.txt" "$KEEP/$1"/; }
}
run new "$ROOT"
python3 tools/termtabs/zombie.py "$TMPD/new/serial.txt" "$CYC" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt")
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same drehbuch on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    run old "$OLDWT"
    python3 tools/termtabs/zombie.py "$TMPD/old/serial.txt" "$CYC" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    [ "$f2" -ge 1 ] && echo "  OK    the old tree fails $f2 checks: they measure something" || echo "  FAIL  the old tree passes"
fi
echo "== result =="
[ "$f1" -eq 0 ] && echo "  OK    all checks pass" || echo "  FAIL  $f1 failed"
[ "$f1" -eq 0 ] && { [ -z "$OLDREF" ] || [ "${f2:-0}" -ge 1 ]; }
