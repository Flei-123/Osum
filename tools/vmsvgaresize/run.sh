#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vmsvgaresize/run.sh -- the real desktop after host resolution changes (r1004), stick image, -vga vmware.
# Sizes 1280x720 -> 1024x768 -> 1600x900 -> 1024x768 are requested through the VNC SetDesktopSize message (same kernel path as a
# VirtualBox hint). After each one: the screen has the new size, the upper part is NOT black (wallpaper / windows), the taskbar sits at
# the bottom (rows differ from the plain wallpaper), and the first screenshot and the last one (same size) look alike.
# EXTRA_WORDS=<kernel words> are appended to the command line (stale.sh uses them).
# Usage: [EXTRA_WORDS=..] [STICK_DIR=<dir with orientos-usb.img>] [IMG=<file>] [SETTLE=9] bash tools/vmsvgaresize/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/vmsvgaresize
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
SETTLE=${SETTLE:-9}
if [ -n "${IMG:-}" ]; then
    IMAGE=$IMG
elif [ -n "${STICK_DIR:-}" ] && [ -f "$STICK_DIR/orientos-usb.img" ]; then
    IMAGE=$STICK_DIR/orientos-usb.img
else
    mkdir -p "$T/build"
    PARTTAB=mbr bash tools/usbimg/build.sh "$T/build" >"$T/build.log" 2>&1 || { echo "stick build failed"; tail -15 "$T/build.log"; exit 1; }
    IMAGE=$T/build/orientos-usb.img
fi
KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
D=$T/run; mkdir -p "$D"
cp -f "$IMAGE" "$D/stick.img"
off=$((2048 * 512))
mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || exit 1
sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
awk -v ex="${EXTRA_WORDS:-}" 'BEGIN{d=0} /^ *cmdline:/ && d==0 { d=1; print $0 " vmsvgahints " ex; next } { print }' "$D/l.conf" >"$D/l2.conf"
mcopy -o -i "$D/stick.img@@$off" "$D/l2.conf" ::/limine.conf
SIZES=${SIZES:-1280x720,1024x768,1600x900,1024x768}
timeout 600 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 4 \
    -device qemu-xhci,id=xhci \
    -drive if=none,id=stick,format=raw,file="$D/stick.img" \
    -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
    -netdev user,id=n0 -device e1000e,netdev=n0 \
    -vga vmware -vnc "unix:$D/vnc.sock" -display none -no-reboot \
    -serial file:"$D/serial.txt" \
    -monitor unix:"$D/mon.sock",server,nowait >"$D/qemu.txt" 2>&1 &
pid=$!
python3 -I "$HERE/resize.py" "$D/mon.sock" "$D/vnc.sock" "$D/o" "$D/serial.txt" "$SETTLE" "$SIZES" >"$D/py.txt" 2>&1 || true
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
[ -n "${KEEP:-}" ] && mkdir -p "$KEEP" && cp -f "$D"/o.*.ppm "$D"/o.res "$D"/o.early "$D"/serial.txt "$KEEP"/ 2>/dev/null
[ "$(cat "$D/o.login" 2>/dev/null)" = 1 ] && ok "logged in" || { bad "login"; tail -5 "$D/py.txt"; }
cat "$D/o.res" 2>/dev/null
n=$(wc -l < "$D/o.res" 2>/dev/null || echo 0)

[ "$n" -ge 3 ] && ok "$n hint steps measured" || bad "only $n hint steps measured"
# r1011: a resize takes the SHARED buffer of a window away (detach: the old row length no longer fits) and the client must hang a new one
# on (attach, WM_SETBUF). Per resize step the serial line `wm: shared ... attach=A detach=D` must not show more detaches than attaches,
# and in total attach >= detach: a window that stays on a private buffer is painted by a kernel copy again for good.
shd=$(grep -a '^wm: shared' "$D/serial.txt" | grep -oE 'attach=[0-9]+ detach=[0-9]+' | uniq | sed 's/attach=//; s/detach=//')
if [ -n "$shd" ]; then
    echo "$shd" | awk -v OFS=' ' 'BEGIN{pa=-1} {if (pa>=0 && ($2-pd)>($1-pa)) {worse++; print "  NOTE  step attach +" ($1-pa) ", detach +" ($2-pd)} pa=$1; pd=$2} END{exit worse>0}' && ok "shared buffers: every resize step re-attached at least as many windows as it detached" || bad "shared buffers: a resize step detached more windows than were re-attached"
    la=$(echo "$shd" | tail -1 | cut -d' ' -f1); ld=$(echo "$shd" | tail -1 | cut -d' ' -f2)
    [ "$la" -ge "$ld" ] && ok "shared buffers: attach $la >= detach $ld" || bad "shared buffers: attach $la < detach $ld"
else
    bad "shared buffers: no 'wm: shared' line in the serial log"
fi
# W-C3f: per window (serial `wm: bufchg <kind> win=<id> bytes=<n> own=<task>`, kind 0 = detach failed, 1 = detach, 2 = attach): no detach may
# fail for lack of contiguous frames, and no window of the TASKBAR process may END on a detach (its client never hung a new shared buffer on:
# blank bar). Before the fix a repeated same-size WM_SIZE detached the bar and the client (size unchanged) never re-attached. Other owners
# are not judged: the desktop program closes its window at a resize and makes a new one (a detach without attach, by design).
nfail=$(grep -ac '^wm: bufchg 0 ' "$D/serial.txt")
[ "$nfail" = 0 ] && ok "buffer changes: no detach failed (no contiguous frames)" || bad "buffer changes: $nfail detach(es) failed"
barpid=$(grep -a 'desk: start /bin/taskbar' "$D/serial.txt" | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
if grep -aq '^wm: bufchg ' "$D/serial.txt" && [ -n "$barpid" ]; then
    nstuck=$(grep -a '^wm: bufchg ' "$D/serial.txt" | awk -v bp="own=$barpid" '$6==bp {k=$3; w=$4; last[w]=k} END{n=0; for (w in last) if (last[w]==1) {n++; print "  NOTE  taskbar window " w " ended on a detach" > "/dev/stderr"}; print n}')
    [ "$nstuck" = 0 ] && ok "buffer changes: every detached taskbar window got a new shared buffer (task $barpid)" || bad "buffer changes: $nstuck taskbar window(s) ended detached"
else
    bad "buffer changes: no 'wm: bufchg' line or no taskbar pid in the serial log"
fi
while read -r i rw rh black rows lastb ew eh dup mcx mbot mw mh ccx cbot cw ch; do
    s=${ew}x${eh}
    [ "$rw" = "$ew" ] && [ "$rh" = "$eh" ] && ok "$s: screen has the new size" || bad "$s: screen size (got ${rw}x${rh})"
    # W-C3g: the taskbar must SEE every size change (serial `taskbar: follow screen w=W h=H`, printed without /etc/uitrace). Before the fix its
    # quiet-mode poll counter had a fixed parity, so `round % 8` (heads_step) never hit in half of all runs and in VirtualBox the bar never followed.
    nfol=$(grep -ac "taskbar: follow screen w=$ew h=$eh" "$D/serial.txt")
    [ "$nfol" -ge 1 ] && ok "$s: taskbar followed the size change ($nfol x)" || bad "$s: taskbar never saw the size change (no 'taskbar: follow screen')"
    awk -v b="$black" 'BEGIN{exit !(b<0.5)}' && ok "$s: desktop not black (black share $black)" || bad "$s: desktop black (black share $black)"
    [ "$rows" -ge 20 ] && ok "$s: taskbar at the bottom (rows $rows)" || bad "$s: no taskbar at the bottom (rows $rows)"
    awk -v b="$lastb" 'BEGIN{exit !(b<0.05)}' && ok "$s: last bar row not black (share $lastb)" || bad "$s: last row black (share $lastb)"
    awk -v b="$dup" 'BEGIN{exit !(b<0.5)}' && ok "$s: bar not repeated by a stale stride (dup share $dup)" || bad "$s: bar repeated (dup share $dup)"
    # r1010: the start menu follows a screen size change at once (also while hidden), so the FIRST opening after every resize stands centred
    # above the bar of the NEW size. Before the fix QEMU opened it one step late (centre / bottom of the previous size).
    # The hints come every 25 s on the kernel's clock; the menu screendump can fall on the NEXT hint, so the menu is judged against the size
    # of ITS OWN screendump (mw x mh), not against the size of the earlier bar screenshot.
    if [ "$mcx" -ge 0 ]; then
        d=$(( mcx - mw / 2 )); [ "$d" -lt 0 ] && d=$(( -d ))
        if [ "$d" -le 8 ] && [ "$mbot" -le $(( mh - 40 )) ] && [ "$mbot" -ge $(( mh - 120 )) ]; then
            ok "$s: start menu centred and above the bar (centre $mcx of $mw, bottom $mbot of $mh)"
        else
            bad "$s: start menu stale (centre $mcx of $mw, bottom $mbot of $mh)"
        fi
    else
        bad "$s: start menu not found"
    fi
    # the menu left open by the step before must have followed the resize (centre of its own screendump, above the bar)
    if [ "$i" -ge 2 ]; then
        if [ "$ccx" -ge 0 ]; then
            d=$(( ccx - cw / 2 )); [ "$d" -lt 0 ] && d=$(( -d ))
            if [ "$d" -le 8 ] && [ "$cbot" -le $(( ch - 40 )) ] && [ "$cbot" -ge $(( ch - 120 )) ]; then
                ok "$s: open menu followed the resize (centre $ccx of $cw, bottom $cbot of $ch)"
            else
                bad "$s: open menu stayed behind (centre $ccx of $cw, bottom $cbot of $ch)"
            fi
        else
            ok "$s: open menu closed at the resize (nothing left behind)"
        fi
    fi
done < "$D/o.res"
# r1065: bar rows measured 2 s after each switch (before the settle time): the bar must be on screen at once, also after the revert
while read -r i er; do
    [ "$er" -ge 20 ] && ok "step $i: taskbar visible 2 s after the switch (rows $er)" || bad "step $i: taskbar missing 2 s after the switch (rows $er)"
done < "$D/o.early"
# r1061: the floating probe window (kgui hint player) shrinks on a smaller screen and gets its size back when the screen grows again;
# the line is printed right after each hint, BEFORE the window server has composed the new size, so each line shows the state after the
# PREVIOUS hint: hints 1280x720, 800x600, 1024x768 give `full full small full` (small = shrunk by the 800x600 screen, full again at 1024x768).
# `wm: refit probe WxH`. Only judged when the run prints probe lines (vmsvgahints).
if grep -aq '^wm: refit probe' "$D/serial.txt"; then
    prev=""
    while read -r pw ph; do
        sw_=$(awk -v w="$pw" 'BEGIN{print (w<900)?"small":"full"}')
        echo "  NOTE  probe ${pw}x${ph} ($sw_)"
        prev="$prev $sw_"
    done < <(grep -a '^wm: refit probe' "$D/serial.txt" | head -n "${PROBE_N:-4}" | sed 's/^wm: refit probe //; s/x/ /')
    echo "$prev" > "$D/probe.seq"
    [ -n "${KEEP:-}" ] && cp -f "$D/probe.seq" "$KEEP"/
    if [ -n "${PROBE_EXPECT:-}" ]; then
        got=$(echo $prev)
        [ "$got" = "$PROBE_EXPECT" ] && ok "probe window sizes follow the screen ($got)" || bad "probe window sizes: got '$got', expected '$PROBE_EXPECT'"
    fi
fi
echo "resize: $pass ok, $fail fail"
[ "$fail" = 0 ]
