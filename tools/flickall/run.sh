#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap '[ -n "${FLICKALL_KEEP:-}" ] && { mkdir -p "$FLICKALL_KEEP"; for v in new old; do mkdir -p "$FLICKALL_KEEP/$v"; cp "$TMPD/$v"/serial.txt "$TMPD/$v"/fahren.log "$TMPD/$v"/ref*.ppm "$TMPD/$v"/post.ppm "$FLICKALL_KEEP/$v/" 2>/dev/null; cp "$TMPD/$v.res" "$FLICKALL_KEEP/" 2>/dev/null; done; }; rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
export EH_SMP=${EH_SMP:-1}
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify osk osktest"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { sed -n "s/.* $1=\([0-9]*\).*/\1/p" "$2" | head -1; }
: > "$TMPD/pd"
for v in new old; do
    xf=()
    [ $v = old ] && xf=(xfile=/etc/paintdirect="$TMPD/pd")
    bash tools/design/eh6.sh "$TMPD/$v" res=1280x800 accel=kvm ton=ja mode=light progs="$PROGS" lang=en tafel=nein \
        drehbuch="$(pwd)/tools/flickall/book.txt" ${xf[@]+"${xf[@]}"} > "$TMPD/$v.log" 2>&1 < /dev/null
    python3 -I tools/flickall/judge.py "$TMPD/$v" > "$TMPD/$v.res" 2>&1
    sed 's/^/  '"$v"': /' "$TMPD/$v.res"
    total=$(num total "$TMPD/$v.res"); atomic=$(num atomic "$TMPD/$v.res"); plain=$(num plain "$TMPD/$v.res")
    frames=$(num frames "$TMPD/$v.res"); half=$(num half "$TMPD/$v.res"); states=$(num state_rows "$TMPD/$v.res")
    if [ -z "$frames" ] || [ -z "$total" ]; then bad "$v: no measurement"; tail -5 "$TMPD/$v.log"; continue; fi
    [ "$frames" -ge 80 ] && ok "$v: $frames frames of the repaint series" || bad "$v: only $frames frames"
    [ "${states:-0}" -gt 0 ] && ok "$v: the two key states differ ($states rows)" || bad "$v: shift does not change the keyboard"
    if [ $v = new ]; then
        [ "$total" -ge 3 ] && [ "$atomic" = "$total" ] && ok "new: every fUi window paints a private picture ($atomic of $total)" || bad "new: $atomic of $total windows private"
        [ "$plain" -ge 2 ] && ok "new: frameless windows covered ($plain)" || bad "new: only $plain frameless windows seen"
        [ "$half" = 0 ] && ok "new: no half-painted keyboard frame" || bad "new: $half half-painted keyboard frames"
    else
        [ "$atomic" = 0 ] && ok "old: paintdirect paints in place ($total windows)" || bad "old: $atomic windows still private"
        [ "$half" -ge 2 ] && ok "old counter-proof: $half half-painted keyboard frames" || bad "old counter-proof sees only $half half-painted frames"
    fi
done
echo "FLICKALL: $pass passed, $fail failed"
[ "$fail" = 0 ]
