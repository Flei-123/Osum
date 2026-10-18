#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/alive.sh -- r1088: after a tab is closed the shell that stays must still run commands (VBox z16: "sh: bye", input dead).
#
#   [OLDREF=<ref>] bash /root/jarvis/bin/heavy bash tools/termtabs/alive.sh
#
# One boot of the stick's machine (tools/design/eh6.sh, KVM, /bin/term built). The drehbuch opens tab 2 and tab 3, closes the shown tab
# (Ctrl+Shift+W) and types `echo OKn` into the tab that stays; it repeats that with a second close and a Ctrl+Tab switch in between and ends
# with a lone terminal. tools/termtabs/alive.py reads the terminal contents the kernel dumps to the serial line (`wm: tw`): every `echo OKn`
# must be answered by a line `OKn` of its own and no window may say `sh: bye`. The kernel dumps only every 5-30 s, so only the echoes whose
# window stays open past a dump (OK0, OK4, OK6 in the first tab, OK10 at the end) are REQUIRED; the others are reported (INFO). OLDREF=<ref> runs the same drehbuch on an older tree for comparison (informational: the VirtualBox failure did not reproduce on QEMU).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
cat > "$TMPD/dreh.txt" <<'DREH'
warteauf 'launcher: ready' || 120
warte 8
klick 300,600
warte 1
tippe echo OK0
taste ret
warte 2
marke tt: new win=
taste ctrl-shift-t
warteneu tt: new win= || 40
warte 4
tippe echo OK1
taste ret
warte 2
marke tt: new win=
taste ctrl-shift-t
warteneu tt: new win= || 40
warte 4
tippe echo OK2
taste ret
warte 2
marke tt: close win=
taste ctrl-shift-w
warteneu tt: close win= || 20
warte 4
tippe echo OK3
taste ret
warte 3
taste ctrl-tab
warte 3
tippe echo OK4
taste ret
warte 3
taste ctrl-tab
warte 3
tippe echo OK5
taste ret
warte 3
marke tt: close win=
taste ctrl-shift-w
warteneu tt: close win= || 20
warte 4
tippe echo OK6
taste ret
warte 35
marke tt: new win=
taste ctrl-shift-t
warteneu tt: new win= || 40
warte 4
marke tt: new win=
taste ctrl-shift-t
warteneu tt: new win= || 40
warte 4
taste ctrl-tab
warte 3
tippe echo OK7
taste ret
warte 3
marke tt: close win=
taste ctrl-shift-w
warteneu tt: close win= || 20
warte 4
tippe echo OK8
taste ret
warte 3
taste ctrl-tab
warte 3
tippe echo OK9
taste ret
warte 3
marke tt: close win=
taste ctrl-shift-w
warteneu tt: close win= || 20
warte 4
tippe echo OK10
taste ret
warte 35
foto a-end
warte 12
DREH
run() { # run <outdir> <worktree>
    (cd "$2" && DESIGNBUILD="$TMPD/build-$1" bash tools/design/eh6.sh "$TMPD/$1" accel=kvm moreprogs=term drehbuch="$TMPD/dreh.txt" > "$TMPD/$1.log" 2>&1)
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$1.log" | head -3
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP/$1"; cp "$TMPD/$1/serial.txt" "$KEEP/$1"/; }
}
run new "$ROOT"
python3 tools/termtabs/alive.py "$TMPD/new/serial.txt" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt")
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same drehbuch on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    run old "$OLDWT"
    python3 tools/termtabs/alive.py "$TMPD/old/serial.txt" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    echo "  INFO  the old tree fails $f2 checks (r1088 did NOT reproduce on QEMU 1 CPU: the gate is a regression guard, no counter-proof is demanded)"
fi
echo "== result =="
[ "$f1" -eq 0 ] && echo "  OK    all checks pass" || echo "  FAIL  $f1 failed"
[ "$f1" -eq 0 ]
