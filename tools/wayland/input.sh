#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wayland/input.sh -- ROUND WAYLAND-INPUT: KEYBOARD, POINTER AND CLIPBOARD OF wayd, with a real libwayland client.
#
#   bash tools/wayland/input.sh [<work dir>]        (start it through /root/jarvis/bin/heavy)
#
# Three programs (tools/wayland/wlin.c, libwayland-client 1.21 + xdg-shell, static musl, started three times: C, A, B) run on wayd in
# the real window server. The host sends REAL input over the QEMU monitor (sendkey, mouse), reads what each program saw from the
# serial line, and checks it:
#
#   2. the keymap: wl_keyboard.keymap = a memfd with the xkb text of the layout; size and CRC are those of the file the host compiled
#      with libxkbcommon (tools/wayland/genkeys.py), repeat_info, seat name, seat version
#   3. focus: only the focused program gets keys (the counter-proof: the others get nothing); a click moves the focus
#      (wl_keyboard.leave / enter with serials)
#   4. keys: the key codes and modifiers wayd sent are fed into libxkbcommon on the host the way a client does -- the keysyms must
#      be  a A 1 exclam Ctrl+c Up
#   5. the pointer: enter / motion / button / frame / leave with window coordinates (24.8), and the position is the one clicked
#   6. the clipboard: client to client (set_selection, offer, receive through a descriptor), into the OrientOS clipboard and out of
#      it; the counter-proofs: no set_selection -> selection=none, a wrong serial is refused, a client that dies empties the selection
#   7. the locked screen gives and takes nothing
#   8. the layout switch (Ctrl+Alt+L): every keyboard gets the keymap of the new layout; the keys of the German layout come out right
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }

TMPD=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
WLB=${WLBUILD:-/root/wl-build}
PROGS="sh sleep echo cat ls wayd"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if python3 tools/wayland/gen.py 2>/dev/null | cmp -s - kernel/user/wlproto.fi; then
    ok "wlproto.fi is what gen.py generates"
else
    bad "kernel/user/wlproto.fi differs from tools/wayland/gen.py"
fi
if python3 tools/wayland/genkeys.py 2>/dev/null | cmp -s - kernel/user/wl_keytab.fi; then
    ok "wl_keytab.fi is what genkeys.py generates (from the host's libxkbcommon)"
else
    bad "kernel/user/wl_keytab.fi differs from tools/wayland/genkeys.py"
fi
python3 tools/wayland/genkeys.py --keymaps "$TMPD/km" 2>"$TMPD/km.txt" \
    && ok "keymaps compiled by libxkbcommon and compiled AGAIN from their own text: $(tr '\n' ' ' < "$TMPD/km.txt")" \
    || bad "keymap generation: $(cat "$TMPD/km.txt")"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs (wayd with wl_input, wl_data, wl_msg)"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'
    echo "WL-INPUT: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "WL-INPUT: $pass passed, $fail failed"; exit 1
fi
if [ -f "$WLB/musl-root/lib/libwayland-client.a" ] && musl-gcc -static -O2 -nostartfiles \
        -T tools/foreign/osum.ld -Wl,--build-id=none -D_GNU_SOURCE \
        -I"$WLB/musl-root/include" -I"$WLB/wayland-1.21.0/gen" -o "$TMPD/wlin" \
        tools/foreign/start.s tools/foreign/osum_main.c tools/wayland/wlin.c \
        "$WLB/wayland-1.21.0/gen/xdg-shell-protocol.c" \
        -L"$WLB/musl-root/lib" -lwayland-client -lffi 2>"$TMPD/wl.txt"; then
    ok "wlin: a Wayland program, libwayland-client + xdg-shell, static musl"
else
    bad "wlin does not build (needs $WLB, docs/RUNDE-WAYLAND.md 9)"
    grep -v 'GNU-stack\|deprecated' "$TMPD/wl.txt" | head -5 | sed 's/^/        /'
    echo "WL-INPUT: $pass passed, $fail failed"; exit 1
fi

if musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld -Wl,--build-id=none -o "$TMPD/idle" \
        tools/foreign/start.s tools/foreign/osum_main.c tools/wayland/idle.c 2>"$TMPD/idle.txt"; then
    ok "idle: counts the system calls of the whole system over a pause"
else
    bad "idle does not build"; head -3 "$TMPD/idle.txt" | sed 's/^/        /'
fi

# three programs: C first (slot 0), then A (slot 1), B last -- the newest window has the focus, so B starts with it.
cat > "$TMPD/g.sh" <<'EOS'
wayd /tmp/wayland-0 2000000000 &
sleep 2
idle 5000 wayd-alone
wlin /tmp/wayland-0 900 C badserial &
sleep 5
wlin /tmp/wayland-0 900 A copy=hello-from-A &
sleep 5
wlin /tmp/wayland-0 900 B paste &
sleep 5
echo ==W-READY==
sleep 700
echo ==FERTIG==
EOS
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/ /etc/ /usr/ /usr/share/ /usr/share/wayd/
   "/usr/share/wayd/keymap-us.xkb=$TMPD/km/keymap-us.xkb" "/usr/share/wayd/keymap-de.xkb=$TMPD/km/keymap-de.xkb"
   "/bin/wlin=$TMPD/wlin" "/bin/idle=$TMPD/idle" "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
# BASE_WAYD=<elf> runs the idle measurement against another wayd (the one before this round: a busy loop) -- with IDLE_ONLY=1
for p in $PROGS; do
    if [ "$p" = wayd ] && [ -n "${BASE_WAYD:-}" ]; then A+=("/bin/wayd=$BASE_WAYD"); else A+=("/bin/$p=$TMPD/bin/$p.elf"); fi
done

python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "WL-INPUT: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot: window server, wayd, three Linux Wayland programs =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 900 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/qemu.txt" 2>&1 &
QPID=$!
waitfor() { # marker seconds
    local i=0
    while [ $i -lt $(( $2 * 5 )) ]; do
        grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0
        kill -0 "$QPID" 2>/dev/null || return 1
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
clean() { tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" | tr -d '\r'; }
L() { clean | grep -ao "wlin\[$1\]: .*"; }       # all lines of one program
lines() { L "$1" | wc -l; }
# the lines of program $1 after the mark (mark = number of lines at that moment)
since() { L "$1" | tail -n +$(( $2 + 1 )); }
declare -A M
mark() { local x; for x in A B C; do M[$x]=$(lines $x); done; }
keys() { # monitor commands, one key each
    : > "$TMPD/k.txt"; local k; for k in "$@"; do echo "sendkey $k" >> "$TMPD/k.txt"; done
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/k.txt" 0.4 > /dev/null 2>&1
    sleep 2
}
klick() { # x y  (screen)
    python3 tools/themestore/click.py "$1,$2" > "$TMPD/c.txt" 2>/dev/null
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/c.txt" > /dev/null 2>&1
    sleep 2
}
# A click that is meant to move the focus: the relative mouse of the monitor can drift under load, so a click that did not land on
# the window (no button press seen by it) is tried again, three times at most.
focusclick() { # program slot
    local n=0 m
    while [ $n -lt 3 ]; do
        m=$(lines "$1")
        klick $(gx "$2" 40) $(gy "$2" 30)
        L "$1" | tail -n +$(( m + 1 )) | grep -qa "button=272 state=1" && return 0
        n=$((n + 1))
    done
    return 1
}
has()    { grep -qaF -- "$2" <<< "$1" && ok "$3" || { bad "$3 -- '$2' missing"; }; }
hasnot() { grep -qaF -- "$2" <<< "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
num() { sed -E "s/.* $2=([0-9]+).*/\1/" <<< "$1" | head -1; }

if [ -n "${IDLE_ONLY:-}" ]; then
    waitfor "idle[wayd-alone]" 120
    sleep 8
    ID0=$(clean | grep -ao 'idle\[wayd-alone\]: syscalls=[0-9]* in [0-9]* ms ([0-9]* per second)' | tail -1)
    printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
    wait "$QPID" 2>/dev/null
    echo "IDLE ONLY: $ID0"
    exit 0
fi
if waitfor "==W-READY==" 400; then
    ok "the three programs are up"
else
    bad "the script did not get ready"; clean | tail -30 | sed 's/^/        /'
fi
sleep 3
for x in A B C; do
    L $x | grep -qa "window up" && ok "wlin[$x] opened its window on wayd" || bad "wlin[$x] has no window"
done
# the window geometry as wayd printed it: slot, x, y, inx, iny
geom() { clean | grep -ao "wayd: window c=$1 x=[0-9]* y=[0-9]* inx=[0-9]* iny=[0-9]* w=[0-9]* h=[0-9]*" | tail -1; }
gx() { local g; g=$(geom $1); echo $(( $(num "$g" x) + $(num "$g" inx) + $2 )); }
gy() { local g; g=$(geom $1); echo $(( $(num "$g" y) + $(num "$g" iny) + $2 )); }
note "slots: C $(geom 0 | cut -c14-)  A $(geom 1 | cut -c14-)  B $(geom 2 | cut -c14-)"

echo "== 2b. idle: wayd sleeps in poll() =="
ID0=$(clean | grep -ao 'idle\[wayd-alone\]: syscalls=[0-9]* in [0-9]* ms ([0-9]* per second)' | tail -1)
note "$ID0"
n0=$(num "$ID0" syscalls)
[ -n "$n0" ] && [ "$n0" -lt 2000 ] && ok "no client, no window: the whole system made $n0 system calls in 5 s (a busy loop makes tens of thousands)" \
    || bad "idle with wayd alone: '$ID0'"

echo "== 3. the keymap =="
FSIZE_US=$(( $(stat -c%s "$TMPD/km/keymap-us.xkb") + 1 ))
CRC_US=$(python3 -c "import zlib,sys;print('0x%08x'%zlib.crc32(open('$TMPD/km/keymap-us.xkb','rb').read()))")
for x in A B C; do
    km=$(L $x | grep -a "keymap fmt" | head -1)
    has "$km" "fmt=1 size=$FSIZE_US crc=$CRC_US head=xkb_keymap" "wlin[$x]: the keymap is the file the host compiled (size $FSIZE_US, crc $CRC_US)"
done
rp=$(L A | grep -a "repeat rate" | head -1)
has "$rp" "rate=25 delay=400" "wl_keyboard.repeat_info (seat version 5)"
has "$(L A | grep -a 'seat caps')" "caps=3 version=5" "seat: pointer + keyboard, version 5"
has "$(L A | grep -a 'seat name')" "name=seat0" "wl_seat.name"

echo "== 4. focus: the newest window (B) has the keyboard, the others get nothing =="
has "$(L B)" "kb enter" "B got wl_keyboard.enter at once (it holds the focus)"
has "$(L B | grep -a 'selection')" "selection=none" "B: nothing was copied yet -> selection=none (no set_selection, no offer)"
mark
keys a
sleep 1
has "$(since B ${M[B]})" "key=30 state=1" "B: the key 'a' arrived as evdev 30 (pressed)"
has "$(since B ${M[B]})" "key=30 state=0" "B: ... and released"
hasnot "$(since A ${M[A]})" "key=" "COUNTER-PROOF: A (no focus) got no key"
hasnot "$(since C ${M[C]})" "key=" "COUNTER-PROOF: C (no focus) got no key"

echo "== 5. a click moves the focus and the pointer =="
mark
AX=$(gx 1 40); AY=$(gy 1 30)
klick $AX $AY
sa=$(since A ${M[A]}); sb=$(since B ${M[B]})
has "$sa" "kb enter" "A got wl_keyboard.enter after the click"
has "$sb" "kb leave" "B got wl_keyboard.leave"
has "$sa" "ptr enter" "A: wl_pointer.enter"
# the pointer travelled over the screen to get here: enter came where it first touched the window, the position that counts is the
# last motion before the button
pe=$(grep -a "ptr motion" <<< "$sa" | tail -1)
ex=$(num "$pe" x); ey=$(num "$pe" y)
if [ "${ex:-x}" -ge 36 ] && [ "${ex:-x}" -le 44 ] && [ "${ey:-x}" -ge 26 ] && [ "${ey:-x}" -le 34 ]; then
    ok "the pointer stood at window coordinates ($ex,$ey) when it was clicked at (40,30), +-4"
else
    bad "pointer at ($ex,$ey), expected about (40,30)"
fi
has "$sa" "ptr button serial=" "A: wl_pointer.button"
has "$sa" "button=272 state=1" "... BTN_LEFT pressed"
has "$sa" "button=272 state=0" "... and released"
has "$sa" "ptr frame" "wl_pointer.frame closes the group"
hasnot "$sb" "ptr button" "COUNTER-PROOF: B (the click was not on it) got no button, though the pointer passed over it on its way"
# a key now goes to A
mark
keys b
has "$(since A ${M[A]})" "key=48 state=1" "the key 'b' (evdev 48) goes to A now"
hasnot "$(since B ${M[B]})" "key=" "... and not to B"
# the pointer leaves: click on the empty desktop
mark
klick 900 600
has "$(since A ${M[A]})" "ptr leave" "A: wl_pointer.leave when the pointer left the window"

echo "== 6. keysyms: what a real client makes of the keys (libxkbcommon on the host) =="
mark
keys shift-a 1 shift-1 ctrl-c ret left up delete
since A ${M[A]} | grep -aE "^wlin\[A\]: (mods|key) " > "$TMPD/keys.txt"
syms=$(python3 tools/wayland/keycheck.py us < "$TMPD/keys.txt")
note "$syms"
[ "$syms" = "syms: A 1 exclam Ctrl+c Return Left Up Delete" ] \
    && ok "A, 1, ! (Shift+1), Ctrl+c, Return, Left, Up, Delete -- the keysyms of the US keymap (arrows and Delete arrive as ESC sequences)" \
    || bad "keysyms: '$syms', expected 'A 1 exclam Ctrl+c Return Left Up Delete'"
has "$(cat "$TMPD/keys.txt")" "mods serial=" "wl_keyboard.modifiers events came with the keys"
has "$(cat "$TMPD/keys.txt" | grep -a 'depressed=4')" "depressed=4" "Ctrl is xkb mask 4"
ser1=$(grep -ao "serial=[0-9]*" "$TMPD/keys.txt" | tr -dc '0-9\n' | sort -n | uniq -d | head -1)
[ -z "$ser1" ] && ok "every event of these keys has its own serial" || bad "serial $ser1 appears twice"

echo "== 7. the clipboard =="
# A copied at its first key press (the Shift of 'shift-a', serial of that key)
sa=$(L A)
has "$sa" "set_selection serial=" "A: set_selection with the serial of a key press"
has "$sa" "selection offers=2" "A (focused) is told the selection too (its own offer, 2 types)"
mark
focusclick B 2
sb=$(since B ${M[B]})
has "$sb" "kb enter" "B got the focus"
has "$sb" "offer mime=text/plain;charset=utf-8" "B: wl_data_offer.offer text/plain;charset=utf-8 (A's source)"
has "$sb" "paste=hello-from-A" "B received the text THROUGH A (receive with a descriptor, source.send): hello-from-A"
has "$(L A)" "source send mime=text/plain;charset=utf-8 wrote=12" "A: wl_data_source.send reached it with a descriptor and A wrote 12 octets"
has "$sb" "sysclip=hello-from-A" "WL -> SYSTEM: the OrientOS clipboard holds A's text (read by a native system call)"
# the system clipboard -> Wayland
mark
keys f9
sb=$(since B ${M[B]})
has "$sb" "native clip_set r=0" "a native program (B, by the bus call) copied 'native-says-hi'"
has "$sb" "paste=native-says-hi" "SYSTEM -> WL: B was offered it and pasted it"
# the wrong serial
echo "== 7b. COUNTER-PROOFS of the clipboard =="
mark
focusclick C 0
keys x
sc=$(since C ${M[C]})
has "$sc" "set_selection serial=" "C: set_selection with a wrong serial"
has "$sc" "source cancelled" "... was REFUSED (wl_data_source.cancelled)"
hasnot "$(L B)$(L A)" "paste=evil" "... and nothing of it was offered to anybody"
# A copies again, then A dies: it exits at once, without destroying its source and without disconnecting
mark
focusclick A 1
keys f8
has "$(since A ${M[A]})" "set_selection serial=" "A copies again (F8)"
mark
keys f6
has "$(since A ${M[A]})" "exit now" "A dies (exit without a word to the compositor)"
sleep 3
mark
focusclick B 2
sb=$(since B ${M[B]})
has "$sb" "selection=none" "the owner died: the selection is EMPTY for the next client (B)"
hasnot "$sb" "paste=hello-from-A" "... no ghost of the dead owner is offered"
mark
keys a
has "$(since B ${M[B]})" "key=30 state=1" "wayd still works after the client died (no hang): B gets keys"

echo "== 8. the locked screen =="
mark
keys f10
has "$(since B ${M[B]})" "lock on r=0 locker=0" "B locks the screen (osum_sperre) and is the locker"
mark
keys a b
klick $(gx 2 40) $(gy 2 30)
hasnot "$(since B ${M[B]})" "key=" "LOCKED: no key reached the window"
hasnot "$(since B ${M[B]})" "ptr " "LOCKED: no pointer event reached the window"
sleep 12
has "$(since B ${M[B]})" "lock off r=0" "the screen is unlocked again (by the program that locked it)"
mark
keys a
has "$(since B ${M[B]})" "key=30 state=1" "after the unlock the keys arrive again"

echo "== 9. the layout switch =="
mark
keys ctrl-alt-l
sleep 3
FSIZE_DE=$(( $(stat -c%s "$TMPD/km/keymap-de.xkb") + 1 ))
CRC_DE=$(python3 -c "import zlib;print('0x%08x'%zlib.crc32(open('$TMPD/km/keymap-de.xkb','rb').read()))")
has "$(since B ${M[B]} | grep -a 'keymap fmt')" "fmt=1 size=$FSIZE_DE crc=$CRC_DE" "B got the German keymap after Ctrl+Alt+L"
mark
keys z semicolon shift-1
since B ${M[B]} | grep -aE "^wlin\[B\]: (mods|key) " > "$TMPD/dekeys.txt"
syms=$(python3 tools/wayland/keycheck.py de < "$TMPD/dekeys.txt")
note "$syms"
[ "$syms" = "syms: y odiaeresis exclam" ] && ok "z -> y, ; -> ö (UTF-8 over two octets), Shift+1 -> ! on the German layout" \
    || bad "German keysyms: '$syms', expected 'y odiaeresis exclam'"
keys ctrl-alt-l

echo "== 10. idle with three windows open =="
mark
keys f5
sleep 8
ID3=$(since B ${M[B]} | grep -a 'idle syscalls=' | tail -1)
note "$ID3"
n3=$(num "$ID3" syscalls)
[ -n "$n3" ] && [ "$n3" -lt 15000 ] && ok "three windows open, nobody touching: the whole system made $n3 system calls in 5 s (wayd wakes about every 20 ms)" \
    || bad "idle with three windows: '$ID3'"

printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
clean > "$TMPD/ser.klar"
if [ -n "${KEEPSER:-}" ]; then cp "$TMPD/ser.klar" "$KEEPSER"; fi
echo "WL-INPUT: $pass passed, $fail failed"
[ "$fail" = 0 ]
