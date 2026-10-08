#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/zreap/run.sh -- "AFTER SEVERAL PROGRAMS NO FURTHER ONE OPENS" (Dell, 04.10.2026).
#
#   bash tools/zreap/run.sh [cycles]
#
# Justin's Dell: after a few programs nothing more could be started (even the
# bridge answered `fork failed`). Cause, measured with the Dell's own image:
# the task table has 32 slots, the system itself holds ~20, and every program
# that ENDS stayed in its slot as a corpse because nobody called wait4 (the
# start menu, the taskbar and the file manager start programs with SYS_EXEC and
# never wait; the boot task parents the login screen and dhcp).
#
# This run (the stick's machine, tools/design/eh6.sh): start the file manager
# from the start menu (Super, "file", Enter), kill it from the terminal, and
# repeat CYCLES times (default 34 -- more than the free slots). Every start
# must work: CYCLES lines `launcher: start ... pid=N`, no `launcher: start refused`.
# Then `ps` must show no pile of corpses. COUNTER-PROOF with the kernel word
# `nozreap` (corpses stay): the starts run out of slots and the menu says so.
set -uo pipefail
cd "$(dirname "$0")/../.."
CYC=${1:-34}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
. "${FIRN:-/root/firn}/tools/testkit/testkit.sh"
{
    echo "warteauf 'launcher: ready' || 120"
    echo "warte 8"
    echo "klick 40,600"
    echo "warte 1"
    echo "tippe ps"
    echo "taste ret"
    echo "warte 3"
    for i in $(seq 1 "$CYC"); do
        echo "marke launcher: start /[^ ]* pid=[0-9]+"
        echo "taste meta_l"
        echo "warte 3"
        echo "tippe file"
        echo "taste ret"
        # wait for THIS start (a fixed sleep lost starts on a loaded host: 33 of 34, also on the old base)
        echo "warteneu launcher: start /[^ ]* pid=[0-9]+ || 25"
        echo "warte 3"
        [ "$i" = 1 ] || [ "$i" = "$CYC" ] && echo "foto c$i"
        echo "klick 40,600"
        echo "warte 1"
        echo "killlast"
        echo "taste ret"
        echo "warte 3"
    done
    echo "tippe ps"
    echo "taste ret"
    echo "warte 4"
} > "$TMPD/dreh.txt"
run() { # run <name> <extra kernel words>
    local name=$1; shift
    bash tools/design/eh6.sh "$TMPD/$name" res=1920x1080 accel=kvm progs="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat" \
        drehbuch="$TMPD/dreh.txt" extra="$*" > "$TMPD/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$name.log" | head -3
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP/$name"; cp "$TMPD/$name/serial.txt" "$KEEP/$name"/; }
}
echo "== corpses are reaped =="
run fix
S="$TMPD/fix/serial.txt"
# (serial lines of different tasks can be glued together: no ^ anchors)
n=$(grep -ao 'launcher: start /[^ ]* pid=[0-9]*' "$S" | wc -l); r=$(grep -ao 'launcher: start refused' "$S" | wc -l); z=$(grep -ao 'kgui: zombie reaped' "$S" | wc -l)
# A start the drive never got (lost key press on a loaded host, `warteneu ... NICHT DA`, 1 of 34 also on the
# old base) is no kernel fault: it does not count against the kernel, 2 at most.
lost=$(grep -ac 'NICHT DA' "$TMPD/fix.log")
if [ "$n" -ge "$CYC" ]; then ok "all $CYC starts worked ($n x 'launcher: start')"
elif [ "$lost" -le 2 ] && [ $((n + lost)) -ge "$CYC" ]; then ok "all starts that were asked for worked ($n of $CYC, $lost never reached the machine: lost input)"
else bad "only $n of $CYC starts worked ($lost lost input)"; fi
[ "$r" -eq 0 ] && ok "no start was refused" || bad "$r starts were refused"
[ "$z" -ge 1 ] && ok "the kernel took corpses away ($z lines 'kgui: zombie reaped')" || bad "no corpse was reaped"
python3 tools/zreap/check.py "$S" fix | sed 's/^/        /'
echo "== counter-proof: nozreap (corpses stay) =="
run old nozreap
S="$TMPD/old/serial.txt"
n2=$(grep -ao 'launcher: start /[^ ]* pid=[0-9]*' "$S" | wc -l); r2=$(grep -ao 'launcher: start refused' "$S" | wc -l)
[ "$r2" -ge 1 ] && ok "without the fix the table fills up: $r2 starts refused after $n2 good ones" || bad "the old kernel never ran out of slots ($n2 starts, none refused)"
python3 tools/zreap/check.py "$S" old | sed 's/^/        /'
echo "== $pass ok, $fail failed =="
[ "$fail" -eq 0 ]
