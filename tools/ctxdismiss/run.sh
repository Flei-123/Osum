#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ctxdismiss/run.sh -- a press OUTSIDE a popup menu dismisses it (kernel/ui/wm.fi popup_outside), a new right click opens the next one.
#
#   [BASE=<rev>] bash tools/ctxdismiss/run.sh
#
# Machine of the stick (tools/design/eh6.sh, 1280x800, QEMU PS/2 mouse; the pad path uses the same button edges in wm on_mouse_btn).
#   1. rklick on the bare desktop -> menu; left click elsewhere -> the menu is GONE (picture as before)
#   2. rklick -> menu; rklick ELSEWHERE -> the old menu is gone and a new one stands at the new place (closes and opens in one press)
#   3. five times: rklick, click outside -> five more menus, all closed again (no menu survives)
#   4. bare task bar: rklick -> menu, click outside -> gone, rklick again -> menu again (`taskbar: kontext leer` twice)
#   5. start menu: open, click outside -> closed (no regression of the existing dismissal)
# COUNTER-PROOF: the tree before the fix (BASE, default HEAD~1): the menu survives the outside click, no second menu ever opens.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
BT=$TMPD/base
cleanup() { git worktree remove --force "$BT" >/dev/null 2>&1; rm -rf "$TMPD"; }
trap cleanup EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"

{
cat <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
foto a0
rklick 900,250
warte 2
foto a1
klick 700,650
warte 2
foto a2
rklick 900,250
warte 2
foto a3
rklick 1000,450
warte 2
foto a4
klick 700,650
warte 2
foto a5
EOF
for n in 1 2 3 4 5; do
cat <<EOF
rklick 900,250
warte 2
foto m$n
klick 700,650
warte 2
foto c$n
EOF
done
cat <<'EOF'
rklick 700,790
warte 2
foto t1
klick 700,650
warte 2
foto t2
rklick 700,790
warte 2
foto t3
klick 700,650
warte 2
foto t4
klickauf start
warte 4
foto s1
klick 1000,450
warte 3
foto s2
EOF
} > "$TMPD/dreh.txt"

run_tree() { # <tree> <out>
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      DESIGNBUILD="$2/build" bash tools/design/eh6.sh "$2/o" res=1280x800 accel=kvm tafel=nein progs="$PROGS" \
        drehbuch="$TMPD/dreh.txt" > "$2/o.log" 2>&1 )
}
diffpix() { # <a.ppm> <b.ppm> <x> <y> <w> <h>
    python3 -I - "$@" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], d[at+1:]
W, a = load(sys.argv[1]); _, b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0
for y in range(y0, y0 + h):
    o = (y * W + x0) * 3
    if a[o:o + w * 3] != b[o:o + w * 3]:
        for x in range(w):
            if a[o + x*3:o + x*3 + 3] != b[o + x*3:o + x*3 + 3]:
                n += 1
print(n)
PY
}

mkdir -p "$TMPD/new" "$TMPD/old"
git worktree add --detach "$BT" "${BASE:-HEAD~1}" >/dev/null 2>&1 || { echo "base worktree failed"; exit 1; }
cp -f tools/design/drive.py "$BT/tools/design/drive.py"
run_tree "$ROOT" "$TMPD/new" &
run_tree "$BT" "$TMPD/old" &
wait
N=$TMPD/new/o; O=$TMPD/old/o
if [ ! -s "$N/s2.ppm" ] || [ ! -s "$O/s2.ppm" ]; then
    bad "no pictures: new=$(ls "$N" 2>/dev/null | wc -l) old=$(ls "$O" 2>/dev/null | wc -l) $(tail -n 3 "$TMPD/new/o.log" | tr '\n' ' ')"
    echo "CTXDISMISS: $pass passed, $fail failed"; exit 1
fi
if [ -n "${CTXDISMISS_OUT:-}" ]; then
    mkdir -p "$CTXDISMISS_OUT/new" "$CTXDISMISS_OUT/old"
    cp "$N"/*.ppm "$N/serial.txt" "$CTXDISMISS_OUT/new/" 2>/dev/null; cp "$O"/*.ppm "$O/serial.txt" "$CTXDISMISS_OUT/old/" 2>/dev/null
fi
# menu rectangles (desktop menu 167x124 at the click point) and the 'gone' threshold: the software pointer stays inside, so allow 400
D1="900 250 167 124"; D2="1000 450 167 124"
gone() { # <dir> <before> <after> <rect...> -> diff count between a state without menu and the one after dismissal
    local dir=$1 a=$2 b=$3; shift 3; diffpix "$dir/$a.ppm" "$dir/$b.ppm" "$@"; }
shows() { # <dir> <before> <menu> <rect...>
    local dir=$1 a=$2 b=$3; shift 3; diffpix "$dir/$a.ppm" "$dir/$b.ppm" "$@"; }

check_tree() { # <dir> <label> <expect: 1 = fixed tree, 0 = old tree>
    local dir=$1 lab=$2 fixed=$3 d
    d=$(shows "$dir" a0 a1 $D1)
    [ "$d" -gt 5000 ] && ok "$lab: right click shows the menu ($d px)" || bad "$lab: no menu after the right click ($d px)"
    d=$(gone "$dir" a0 a2 $D1)
    if [ "$fixed" = 1 ]; then
        [ "$d" -le 400 ] && ok "$lab: click outside closes the menu ($d px differ from before)" || bad "$lab: menu survived the outside click ($d px)"
    else
        [ "$d" -gt 5000 ] && ok "$lab: COUNTER-PROOF: the menu SURVIVES the outside click ($d px)" || bad "$lab: COUNTER-PROOF: menu gone even without the fix ($d px)"
    fi
    if [ "$fixed" = 1 ]; then
        d=$(gone "$dir" a0 a2 0 0 170 38)
        [ "$d" -le 600 ] && ok "$lab: no stale menu picture at the top left after the dismissal ($d px; pointer only)" || bad "$lab: stale menu picture at the top left ($d px)"
        d=$(shows "$dir" a2 a3 $D1)
        [ "$d" -gt 5000 ] && ok "$lab: second right click shows the menu again ($d px)" || bad "$lab: no second menu ($d px)"
        d=$(gone "$dir" a2 a4 $D1)
        [ "$d" -le 400 ] && ok "$lab: right click elsewhere closed the first menu ($d px)" || bad "$lab: first menu still there ($d px)"
        d=$(shows "$dir" a2 a4 $D2)
        [ "$d" -gt 5000 ] && ok "$lab: and opened the new one at the new place ($d px)" || bad "$lab: no new menu at the new place ($d px)"
        d=$(gone "$dir" a2 a5 $D2)
        [ "$d" -le 400 ] && ok "$lab: new menu closed by the outside click ($d px)" || bad "$lab: new menu survived ($d px)"
        local n
        for n in 1 2 3 4 5; do
            d=$(shows "$dir" a2 m$n $D1); e=$(gone "$dir" a2 c$n $D1)
            [ "$d" -gt 5000 ] && [ "$e" -le 400 ] && ok "$lab: repeat $n opened ($d px) and closed ($e px)" || bad "$lab: repeat $n open=$d closed=$e"
        done
        d=$(shows "$dir" c5 t1 400 730 600 70); e=$(gone "$dir" c5 t2 400 730 600 70)
        local tn; tn=$(grep -ac 'taskbar: kontext leer x=' "$dir/serial.txt")
        [ "$tn" = 2 ] && ok "$lab: bar menu opened twice ($tn lines) after an outside click in between" || bad "$lab: bar menu lines=$tn (want 2)"
        d=$(gone "$dir" c5 s2 0 80 430 660)
        [ "$d" -le 800 ] && ok "$lab: start menu closed by the outside click ($d px)" || bad "$lab: start menu survived the outside click ($d px)"
    else
        local on; on=$(grep -ac 'desktop: context open' "$dir/serial.txt")
        [ "$on" = 1 ] && ok "$lab: COUNTER-PROOF: the menu opened only ONCE in the whole run ($on)" || bad "$lab: COUNTER-PROOF: $on menus opened (old tree should stay at 1)"
    fi
}
check_tree "$N" new 1
check_tree "$O" old 0
n=$(grep -ac 'desktop: context open' "$N/serial.txt")
[ "$n" = 8 ] && ok "new: 8 desktop menus opened in the run (1 + 2 + 5)" || bad "new: expected 8 desktop menus, counted $n"
echo; echo "CTXDISMISS: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
