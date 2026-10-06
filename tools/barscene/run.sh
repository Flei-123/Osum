#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/barscene/run.sh -- r381 STAGE 1: THE TASK BAR IS A WINDOW OF fUi'S SCENE HOST,
# AND ITS RECTANGLES ARE NODES OF A TREE.
#
#   bash tools/barscene/run.sh [<workdir>]
#   BARROOT=/path/to/older/tree bash tools/barscene/run.sh   # counter-proof: the TASK BAR
#       program comes from that tree (e.g. main before r381); the run must then FAIL
#
# The bar was a raw window (`WM_CREATE`) painted band by band into the window server and
# invisible to the accessibility export. Now it is window 0 of the scene host: its own
# painters still paint every rectangle (pixel for pixel the same -- the pictures of
# `tools/themestore`, `look`, `glyphe` ... are the proof), but the rectangles are also ghost
# buttons of a tree, with the names a screen reader says. This runner boots the bar with the
# Windows 11 keys on, reads its tree over the bus like a screen reader (`act call a11y.tree`)
# (and tries to press nodes through it, by the bus action each node carries: taskbar.start,
# taskbar.taskview, taskbar.chevron, taskbar.pin.<name>, taskbar.quick):
#
#   1. the window "Taskbar" is in the tree, with a node for the start button, the task view
#      button, the chevron, every pin, the network field and the clock (role button, the
#      name a human reads)
#   2. a node stands where the bar says it stands (`taskbar: taskview x= y= w= h=` and the
#      bar's own place, `taskbar: geom`) -- the tree is not a guess
#   3. the tree is for READING: the kernel's target rule refuses a press on a system window
#      (layer L_TOP) -- no program may press the start button; the bar sees no click
#   4. the KEYBOARD: Super+T gives the keyboard to the bar, Tab walks the nodes (the focus
#      ring is the host's), Enter presses the focused node like a click in its middle
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
BARROOT=${BARROOT:-$ROOT}

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

if [ -n "${1:-}" ]; then TMPD=$1; mkdir -p "$TMPD"; else TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT; fi
mkdir -p "$TMPD/bin" "$TMPD/barbin"
PROGS="sh ls cat echo sleep orientbus act axd"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
   && (cd "$BARROOT" && FIRNLIB="$BARROOT/lib" bash tools/sync/build.sh "$TMPD/barbin" 0 taskbar) > "$TMPD/b2.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs and the task bar (from $BARROOT)"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" "$TMPD/b2.txt" | sed 's/^/        /'
    echo "BARSCENE: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "BARSCENE: $pass passed, $fail failed"; exit 1
fi

cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
taskbar &
sleep 30
echo ==B-WAIT==
act call a11y.tree window=Taskbar
sleep 6
echo ==B-TREE==
act call a11y.tree window=Taskbar
echo ==B-CHEV==
act call a11y.press action=taskbar.chevron window=Taskbar
sleep 6
echo ==B-TREE2==
act call a11y.tree window=Taskbar
echo ==B-TV==
act call a11y.press action=taskbar.taskview window=Taskbar
sleep 3
echo ==B-KEYS==
sleep 25
echo ==B-END==
act stop
echo ==FERTIG==
EOS
cat > "$TMPD/taskbar.conf" <<'CONF'
# taskbar.conf -- the Windows 11 layout (r387) for the scene test
edge=bottom
height=40
width=104
autohide=0
ontop=1
align=center
labels=never
clock_lines=2
clock_date=1
clock_weekday=0
clock_year4=1
tray_language=1
taskview=1
tray_chevron=1
tray_group=1
badges=1
hide_missing=0
pins=explorer,calc,settings,zip
CONF
printf 'on\n' > "$TMPD/uitrace"

A=(build "$TMPD/disk.img" 32768 --v3 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/
   "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/etc/taskbar.conf=$TMPD/taskbar.conf" "/etc/uitrace=$TMPD/uitrace"
   "/bin/taskbar=$TMPD/barbin/taskbar.elf"
   "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=night\nmode=dark\naccent=\nshape=modern\n' > "$TMPD/theme.conf"
A+=("/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "BARSCENE: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
waitfor() { # marker tries
    local i=0
    while [ $i -lt $2 ]; do
        grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.3; i=$((i + 1))
    done
    return 1
}
keys() { # monitor lines
    printf '%s\n' "$@" > "$TMPD/keys.txt"
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/keys.txt" 0.5 > /dev/null 2>&1
    sleep 1
}
if waitfor "==B-KEYS==" 1000; then
    # Super+T gives the keyboard to the bar; Tab walks to the second node (Start -> Task view);
    # Enter presses it
    keys "sendkey meta_l-t"
    sleep 1
    keys "sendkey tab"
    keys "sendkey ret"
else
    bad "the guest did not reach the keyboard part"
fi
waitfor "==FERTIG==" 400
python3 tools/gfx/screenshot.py "$SOCK" "$TMPD/bar.ppm" 8 > /dev/null 2>&1
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
perl -0pi -e 's/wm: fen i=[^\n]*? tka=\d+\r?\n//g' "$TMPD/ser.klar"
G="$TMPD/ser.klar"

echo "== 3. the tree of the bar =="
part "$G" B-TREE B-CHEV > "$TMPD/t1.txt"
has "$TMPD/t1.txt" '"Taskbar"' "the window of the bar is in the tree, named by its title"
for nm in "Start" "Task view" "Hidden icons" "explorer" "calc" "settings" "zip" "Network"; do
    grep -qaE "=button .*\"$nm\"" "$TMPD/t1.txt" && ok "a button node named '$nm'" || bad "no button node '$nm' ($(grep -ac '=button' "$TMPD/t1.txt") buttons in the tree)"
done
for ac in taskbar.start taskbar.taskview taskbar.chevron taskbar.pin.explorer taskbar.quick; do
    grep -qaF "act=$ac" "$TMPD/t1.txt" && ok "a node carries the bus action $ac" || bad "no node with act=$ac"
done
clk=$(grep -a 'taskbar: text clock ' "$G" | tail -1 | sed 's/.* t=//')
grep -qaE "=button .*\"[0-9][0-9]:[0-9][0-9]\"" "$TMPD/t1.txt" && ok "the clock node says a time (the bar shows \"$clk\")" || bad "no clock node (the bar shows '$clk')"

echo "== 4. a node stands where the bar says =="
geom=$(grep -aoE 'taskbar: geom edge=[0-9]+ x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$G" | tail -1)
gx=$(echo "$geom" | sed 's/.* x=\([0-9]*\) .*/\1/'); gy=$(echo "$geom" | sed 's/.* y=\([0-9]*\) .*/\1/')
tv=$(grep -aoE 'taskview x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$G" | tail -1)
tx=$(echo "$tv" | sed 's/.*x=\([0-9]*\) .*/\1/'); ty=$(echo "$tv" | sed 's/.* y=\([0-9]*\) .*/\1/')
tw=$(echo "$tv" | sed 's/.* w=\([0-9]*\) .*/\1/'); th=$(echo "$tv" | sed 's/.* h=\([0-9]*\)$/\1/')
node=$(grep -aE '=button .*"Task view"' "$TMPD/t1.txt" | head -1)
nxy=$(echo "$node" | grep -oE ' [0-9]+,[0-9]+ [0-9]+x[0-9]+ ' | head -1)
echo "        bar window at $gx,$gy; task view per bar: $tx,$ty ${tw}x$th; node:$nxy"
python3 - "${gx:-0}" "${gy:-0}" "${tx:-0}" "${ty:-0}" "${tw:-0}" "${th:-0}" "$nxy" <<'PY' && ok "the 'Task view' node is the rectangle the bar traced (within 1 pixel)" || bad "the node is not where the bar says"
import re, sys
gx, gy, tx, ty, tw, th = (int(v) for v in sys.argv[1:7])
m = re.match(r'\s*(\d+),(\d+) (\d+)x(\d+)', sys.argv[7])
if not m: sys.exit(1)
nx, ny, nw, nh = (int(v) for v in m.groups())
# the tree's places are the window's own (the window node stands at 0,0)
sys.exit(0 if abs(nx - tx) <= 1 and abs(ny - ty) <= 1 and abs(nw - tw) <= 1 and abs(nh - th) <= 1 else 1)
PY

echo "== 5. the tree is for READING: the kernel's target rule refuses a press on a system window =="
# `ax_press` (kernel/sys/sysgui.fi) presses buttons of application windows only (layer L_NORMAL):
# a program with the bus right must not be able to press the start button, the task view or a
# quick-settings tile of the bar. The bar's nodes are names and places for a screen reader; the
# press is refused with reason 5 and the bar sees no click. (The clicks of the real pointer reach
# the bar through `bar_raw` -- tools/win11bar measures them.)
n=$(grep -ac 'ax: press node=.* refuse=5' "$G")
[ "$n" -ge 2 ] && ok "both presses were refused by the target rule (refuse=5): $n" || bad "presses refused by rule 5: $n (wanted 2)"
part "$G" B-CHEV B-KEYS > "$TMPD/pc.txt"
grep -qaE 'taskbar: click x=' "$TMPD/pc.txt" && bad "a press got through to the bar as a click" || ok "and the bar saw no click"
grep -qaE 'taskbar: chevron .* open=1' "$TMPD/pc.txt" && bad "the chevron opened by a press" || ok "the chevron stayed closed"
part "$G" B-TREE2 B-TV > "$TMPD/t2.txt"
for nm in "Start" "Task view" "Hidden icons"; do
    grep -qaE "=button .*\"$nm\"" "$TMPD/t2.txt" && ok "the node '$nm' is still there after the refused press" || bad "node '$nm' lost"
done

echo "== 6. the keyboard: Super+T, Tab, Enter =="
grep -qaF 'taskbar: keys on' "$G" && ok "Super+T gave the keyboard to the bar (taskbar: keys on)" || bad "no 'keys on' after Super+T"
part "$G" B-KEYS B-END > "$TMPD/k.txt"
grep -qaE 'taskbar: click x=' "$TMPD/k.txt" && ok "Tab + Enter pressed a node: the bar saw a click in the middle of a node" || bad "no click after Tab, Enter"
grep -qaE 'taskview: open n=' "$TMPD/k.txt" && ok "... and it was the second node, Task view: the card opened" || bad "the card did not open (focus on the wrong node?): $(grep -a 'taskbar: click' "$TMPD/k.txt" | head -1)"
grep -qaF 'taskbar: keys off' "$G" && ok "the activation gave the keyboard back (taskbar: keys off)" || bad "the keyboard stayed in the bar"

echo
echo "BARSCENE: $pass passed, $fail failed   (workdir $TMPD)"
[ "$fail" -eq 0 ]
