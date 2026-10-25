#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/popesc/run.sh -- Escape closes the notification card, the quick settings and the task view right after they open
# (no click into the popup first). Counter-proof: the same run with the open-time focus_canvas() calls removed
# must not close any of the three.
#   /root/jarvis/bin/heavy bash tools/popesc/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
FILES="kernel/user/notifc.fi kernel/user/taskview.fi kernel/user/qs.fi"
trap 'git checkout -q -- $FILES 2>/dev/null; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"

run() {
    DESIGNBUILD="$TMPD/build-$1" bash tools/design/eh6.sh "$TMPD/$1" res=1280x800 accel=kvm progs="$PROGS" \
        tbextra="taskview=1" drehbuch="tools/popesc/dreh.txt" > "$TMPD/$1.log" 2>&1 < /dev/null
}

check() {
    local S="$TMPD/$1/serial.txt" want=$2
    if [ ! -s "$S" ]; then bad "$1: no serial log: $(tail -n 3 "$TMPD/$1.log" | tr '\n' ' ')"; return; fi
    grep -a '^panic' "$S" | head -2
    for pat in 'notifc: open n=' 'qs: open x=' 'taskview: open n='; do
        grep -qaE "$pat" "$S" && ok "$1: opened ($pat)" || bad "$1: never opened ($pat)"
    done
    local n=0
    for pat in 'notifc: shut esc' 'qs: closed by escape' 'taskview: shut esc'; do
        if grep -qaF "$pat" "$S"; then n=$((n+1)); [ "$want" = yes ] && ok "$1: Escape reached the popup ($pat)" || bad "$1: $pat although the focus call is gone"
        else [ "$want" = yes ] && bad "$1: no '$pat'" || ok "$1: no '$pat' without the focus call"; fi
    done
}

echo "== A. Escape right after opening =="
run new; check new yes
echo "== B. counter-proof: focus_canvas() removed =="
sed -i '/fuiscene\.focus_canvas()/d' $FILES
run old; check old no
git checkout -q -- $FILES
echo "POPESC: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
