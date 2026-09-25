#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/loginui/run.sh -- ROUND LOGIN-2: THE LOGIN SCREEN, AS JUSTIN USES IT.
#
# Justin's findings on the Dell OptiPlex 9020 (25.09.2026):
#
#   1. the mouse does nothing on the login screen
#   2. one key gives TWO dots
#   3. no eye to show the password -- and it should be ONE password field
#      for the whole system, not one per screen
#   4. Tab only jumps between the password and the name at the top, never
#      to "Anmelden"
#   5. the caret does not blink
#
# 1 and 2 had one cause on that machine: its keyboard and mouse sat on
# EHCI-routed ports (Intel Lynx Point), so the kernel did not drive them;
# the keyboard reached us through the BIOS's PS/2 emulation, whose extra
# IRQ 1 re-read the last byte (kbd.irq), and the mouse not at all
# (xhci.intel_route). That routing is chipset hardware; QEMU cannot
# reproduce it, so what is measured here is the part a machine can check:
#
#   A  the same stick as on the 9020, keyboard and a RELATIVE mouse on
#      xHCI (the 9020's mouse is relative, not a tablet): keys arrive
#      once, the Tab chain, the caret blinks, the eye works with the
#      mouse, the password is not copied, and mouse clicks on the
#      buttons are taken
#   B  the same with the PS/2 keyboard and mouse of the 8042: one key,
#      one character -- the status check in kbd.irq loses no real key
#   C  the kernel side, statically: the port switch and the ghost check
#      are in the source
#
#   bash tools/loginui/run.sh [<build dir>]
set -uo pipefail
SELBST=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)
cd "$SELBST/../.." || exit 1
[ -f tools/osum/mkfs.py ] || { echo "== $(pwd) is not the Osum tree" >&2; exit 1; }
WURZEL=$(pwd)
# Without an argument a FRESH build in a temporary directory -- a build
# left over from an older tree would measure the older tree.
BUILD=${1:-}
if [ -z "$BUILD" ]; then
    BUILD=$(mktemp -d /tmp/loginui-bau.XXXXXX)
    trap 'rm -rf "$BUILD" "$BUILD.log"' EXIT
fi
OK=0
FAIL=0
ok()   { echo "  OK    $*"; OK=$((OK + 1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }
info() { echo "        $*"; }
kopf() { echo; echo "== $*"; }
num() { # num <text> <value> <op> <want>
    local t=$1 v=$2 op=$3 w=$4
    if [ -z "$v" ]; then bad "$t: no number (expected $op $w)"; return; fi
    if [ "$v" -"$op" "$w" ]; then ok "$t: $v"; else bad "$t: $v, expected $op $w"; fi
}
ende() {
    echo; echo "LOGINUI: $OK passed, $FAIL failed"
    [ "$FAIL" -eq 0 ] && exit 0
    exit 1
}

# ------------------------------------------------------------------ build
if [ ! -f "$BUILD/orientos-usb.img" ]; then
    kopf "0. build the stick (UITRACE=1 UIBLINK=1, MBR like the 9020)"
    mkdir -p "$BUILD"
    if UITRACE=1 UIBLINK=1 PARTTAB=mbr bash tools/usbimg/build.sh "$BUILD" \
        > "$BUILD.log" 2>&1; then
        ok "stick built"
    else
        tail -15 "$BUILD.log"; bad "the build failed"; ende
    fi
else
    kopf "0. the existing build is used: $BUILD"
fi
IMG="$BUILD/orientos-usb.img"

# ------------------------------------------------------ C. static checks
kopf "C. the kernel side (source)"
grep -q 'fn intel_route' kernel/drv/usb/xhci.fi \
    && ok "xhci.fi switches Intel ports from EHCI to xHCI (intel_route)" \
    || bad "intel_route is missing in xhci.fi"
grep -q 'IR_XUSB2PR: u64 = 0xD0' kernel/drv/usb/xhci.fi \
    && grep -q 'IR_USB2PRM: u64 = 0xD4' kernel/drv/usb/xhci.fi \
    && ok "XUSB2PR 0xD0 / USB2PRM 0xD4 as in Linux pci-quirks.c" \
    || bad "the routing registers are not the ones Linux uses"
grep -q '(serial.in8(STATUS_PORT) as u64 & 0x21) != 0x01' kernel/drv/hid/kbd.fi \
    && ok "kbd.irq reads 0x60 only with a full output buffer (no ghost byte)" \
    || bad "kbd.irq does not check the 8042 status"
grep -q 'EYE ' lib/icons.fi && grep -q 'EYE_OFF' lib/icons.fi \
    && ok "the icon font has eye and eye-off" \
    || bad "eye icons missing in lib/icons.fi"
for p in glogin lock; do
    grep -q 'wlib.password(' "kernel/user/$p.fi" \
        && ok "$p.fi takes the system's password field (wlib.password)" \
        || bad "$p.fi builds its own password field"
done

# ------------------------------------------------------------ the runner
MON=""
D=""
boot() { # boot <name> <xhci|ps2>
    local name=$1 mode=$2
    D=/tmp/loginui-$name
    rm -rf "$D"; mkdir -p "$D"
    cp -f "$IMG" "$D/stick.img"
    local off=$((2048 * 512))
    mcopy -o -i "$D/stick.img@@$off" ::/limine.conf "$D/l.conf" || return 1
    sed -i 's/^timeout: .*/timeout: 1/' "$D/l.conf"
    mcopy -o -i "$D/stick.img@@$off" "$D/l.conf" ::/limine.conf
    local IN=()
    if [ "$mode" = xhci ]; then
        IN=(-device usb-kbd,bus=xhci.0 -device usb-mouse,bus=xhci.0)
    fi
    local KVM=(-accel tcg)
    [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
    timeout 400 qemu-system-x86_64 "${KVM[@]}" -m 2048 -smp 2 \
        -device qemu-xhci,id=xhci \
        -drive if=none,id=stick,format=raw,file="$D/stick.img" \
        -device usb-storage,bus=xhci.0,drive=stick,bootindex=1 \
        "${IN[@]}" -netdev user,id=n0 -device e1000e,netdev=n0 \
        -vga std -display none -no-reboot \
        -serial file:"$D/serial.txt" \
        -monitor unix:"$D/mon.sock",server,nowait > "$D/qemu.txt" 2>&1 &
    echo $! > "$D/pid"
    MON="$D/mon.sock"
    local i=0
    while [ $i -lt 150 ]; do
        grep -qa 'glogin: bereit' "$D/serial.txt" 2>/dev/null && break
        sleep 1; i=$((i + 1))
    done
    grep -qa 'glogin: bereit' "$D/serial.txt" 2>/dev/null || return 1
    sleep 6
    return 0
}
mon() { python3 - "$MON" "$@" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.settimeout(0.5)
def drain():
    try:
        while s.recv(65536): pass
    except Exception: pass
drain()
for c in sys.argv[2:]:
    if c.startswith('sleep '):
        time.sleep(float(c.split()[1])); continue
    s.sendall((c + '\n').encode()); time.sleep(0.25); drain()
PY
}
halt_vm() { [ -n "$D" ] && kill "$(cat "$D/pid")" 2>/dev/null; sleep 1; }
# the n-th glogin rect of a kind, from its LAST report
rect_of() { grep -aoE "^glogin: rect id=[0-9]+ kind=$1 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$D/serial.txt" | sed -n "${2}p"; }
fld() { echo "$1" | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2; }
# every wlib program writes to the one serial line -- only glogin's lines
GP=""
gpid() { GP=$(grep -aoE 'bereit n=[0-9]+ pid=[0-9]+' "$D/serial.txt" | tail -1 | grep -oE '[0-9]+$'); }
# NOT anchored at the start of the line: the kernel echoes every key
# ("key: a") from the interrupt, and that can land in front of a line a
# program is just writing. The tail of the line is what identifies it.
# A line can still be torn at its END by another program's output (the
# serial line is written octet by octet); then its pid is gone. Such a
# line counts unless it names ANOTHER pid.
foci() { grep -aoE "focus id=[0-9]+ kind=[0-9]+( pid=[0-9]+)?" "$D/serial.txt" \
    | awk -v gp="$GP" '{ p=""; if (match($0, / pid=[0-9]+/)) p=substr($0, RSTART+5, RLENGTH-5);
        if (p == "" || p == gp) { sub(/^focus /, ""); sub(/ pid=.*/, ""); print } }'; }
# lines of glogin: its pid, or no pid at all (torn); never another pid
mine() { awk -v gp="$GP" '{ p=""; if (match($0, / pid=[0-9]+/)) p=substr($0, RSTART+5, RLENGTH-5);
    if (p == "" || p == gp) { sub(/ pid=.*/, ""); print } }'; }
carets() { grep -aoE "caret vis=[01] n=[0-9]+( pid=[0-9]+)?" "$D/serial.txt" | mine; }
eyes() { grep -aoE "eye id=[0-9]+ shown=[01] len=[0-9]+( pid=[0-9]+)?" "$D/serial.txt" | mine | sed 's/^/wlib: /'; }
eyerect() { grep -aoE "eyerect x=[0-9]+ y=[0-9]+ w=[0-9]+ shown=[01] pid=$GP\$" "$D/serial.txt" | tail -1; }
png() { python3 -c "import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2])" "$1" "$2" 2>/dev/null; }
# A RELATIVE mouse to an absolute place: first into the top-left corner
# (the pointer clamps there), then the exact distance in small steps.
zeig() { # zeig <x> <y>
    local cmds=() k=0
    while [ $k -lt 30 ]; do cmds+=("mouse_move -100 -100"); k=$((k + 1)); done
    local x=$1 y=$2
    while [ "$x" -gt 0 ] || [ "$y" -gt 0 ]; do
        local dx=$x dy=$y
        [ "$dx" -gt 50 ] && dx=50
        [ "$dy" -gt 50 ] && dy=50
        cmds+=("mouse_move $dx $dy")
        x=$((x - dx)); y=$((y - dy))
    done
    mon "${cmds[@]}" "sleep 0.5"
    # Measured (25.09.): relative moves arrive exactly; what went wrong in
    # the first runs was CLICKING before the last move was through --
    # so a full second of rest before anyone clicks.
    sleep 1
}
klick() { mon "mouse_button 1" "sleep 0.2" "mouse_button 0" "sleep 1"; }

BEL="$WURZEL/belege/loginui"
mkdir -p "$BEL"

# ================================================ A. xHCI keyboard + mouse
kopf "A. USB keyboard and RELATIVE USB mouse on xHCI (the 9020 once routed)"
if ! boot usb xhci; then
    bad "the login screen did not come up (no 'glogin: bereit')"
    halt_vm; ende
fi
ok "the login screen is up"
gpid; info "glogin runs as pid ${GP:-?}"
grep -aq 'driver=mouse' "$D/serial.txt" && ok "the USB mouse is driven (driver=mouse)" \
    || bad "no 'driver=mouse' -- the mouse is not ours"
PW=$(rect_of 4 1); BTN=$(rect_of 2 1); OTHER=$(rect_of 2 2)
PWID=$(fld "$PW" id); BTNID=$(fld "$BTN" id); OTHID=$(fld "$OTHER" id)
info "password field: $PW"
info "Anmelden:       $BTN"
info "other user:     $OTHER"
if [ -z "$PWID" ] || [ -z "$BTNID" ] || [ -z "$OTHID" ]; then
    bad "the layout is not field + two buttons"; halt_vm; ende
fi
ok "one password field and two buttons on the screen"
NENTRY=$(grep -aoE '^glogin: rect id=[0-9]+ kind=(4|5) ' "$D/serial.txt" | wc -l)
num "visible fields and lists (only the password; the name is a label)" "$NENTRY" eq 1
F0=$(foci | tail -1)
[ "$F0" = "id=$PWID kind=4" ] && ok "the focus starts in the password field ($F0)" \
    || bad "the focus starts elsewhere: '$F0'"

# 5. THE CARET BLINKS
C0=$(carets | wc -l)
sleep 3
C1=$(carets | wc -l)
num "caret phase changes in 3 s (530 ms period)" "$((C1 - C0))" ge 4
# each line carries its change number n: after an odd number of changes
# the caret is off, after an even one on (it starts on). A torn line can
# go missing; a line that disagrees cannot happen with a real blink.
FALSCH=$(carets | awk '{ v=$2; n=$3; sub(/vis=/,"",v); sub(/n=/,"",n); if (v != 1 - n % 2) print }' | wc -l)
V=$(carets | tail -6 | grep -oE 'vis=[01]' | cut -d= -f2 | tr -d '\n')
[ "$FALSCH" -eq 0 ] && ok "and it alternates, on and off by its count: $V" \
    || bad "the caret phase disagrees with its count in $FALSCH lines"

# 2. ONE KEY, ONE CHARACTER (counted below through the eye: len=)
mon "sendkey a" "sleep 0.3" "sendkey b" "sleep 0.3" "sendkey c" "sleep 1"
mon "screendump $D/dots.ppm" "sleep 1"
# 4. THE TAB CHAIN: field -> Anmelden -> other user -> field, and back.
# Measured IN THE PICTURE: after every key, which of the three controls
# carries the focus ring (the trace lines are written octet by octet and
# another program's output can tear one of them apart).
ring() { # ring <ppm> -> the id whose outline is the dark focus colour
    python3 - "$1" "$PW" "$BTN" "$OTHER" <<'PY'
import sys, re
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB')
hits = []
for r in sys.argv[2:]:
    d = dict(re.findall(r'(\w+)=(\d+)', r))
    x, y, h = int(d['x']), int(d['y']), int(d['h'])
    # the left edge, half way down: ring = dark, no ring = light border
    p = [im.getpixel((x + k, y + h // 2)) for k in range(0, 3)]
    if min(sum(c) for c in p) < 300:
        hits.append(d['id'])
print(' '.join(hits) if hits else '-')
PY
}
KETTE=""
k=0
for t in tab tab tab shift-tab shift-tab shift-tab; do
    k=$((k + 1))
    mon "sendkey $t" "sleep 1.2" "screendump $D/tab$k.ppm" "sleep 0.8"
    r=$(ring "$D/tab$k.ppm")
    if [ "$r" = "-" ] || [ -z "$r" ]; then   # mid-repaint or the dump not yet written: once more
        mon "screendump $D/tab$k.ppm" "sleep 0.8"; r=$(ring "$D/tab$k.ppm")
    fi
    KETTE="$KETTE$r "
done
WANT="$BTNID $OTHID $PWID $OTHID $BTNID $PWID "
[ "$KETTE" = "$WANT" ] && ok "Tab chain in the picture: $KETTE(Anmelden, other user, field, and back)" \
    || bad "Tab chain in the picture '$KETTE', expected '$WANT'"
# 3. THE EYE, with the MOUSE (1: the mouse works on the login screen)
EX=$(eyerect)
ex=$(fld "$EX" x); ey=$(fld "$EX" y); ew=$(fld "$EX" w)
if [ -z "$ex" ]; then   # its one line was torn -- the eye is the square at the right end
    ew=$(fld "$PW" h); ex=$(( $(fld "$PW" x) + $(fld "$PW" w) - ew )); ey=$(fld "$PW" y)
    EX="(from the field) x=$ex y=$ey w=$ew"
fi
if [ -z "$ex" ]; then
    bad "no eye position"
else
    ok "the password field has an eye: $EX"
    zeig $((ex + ew / 2)) $((ey + ew / 2))
    klick
    L=$(eyes | tail -1)
    [ "$L" = "wlib: eye id=$PWID shown=1 len=3" ] \
        && ok "a MOUSE click on the eye shows the text -- 3 characters for 3 keys ($L)" \
        || bad "eye click: '$L', expected 'wlib: eye id=$PWID shown=1 len=3'"
    mon "screendump $D/plain.ppm" "sleep 1"
    klick
    L=$(eyes | tail -1 | sed 's/ len=.*//')
    [ "$L" = "wlib: eye id=$PWID shown=0" ] \
        && ok "a second click hides it again" || bad "second eye click: '$L'"
    png "$D/dots.ppm" "$BEL/dots.png"; png "$D/plain.ppm" "$BEL/plain.png"
    D1=$(python3 - "$D/dots.ppm" "$D/plain.ppm" "$(fld "$PW" x)" "$(fld "$PW" y)" "$(fld "$PW" w)" "$(fld "$PW" h)" <<'PY'
import sys
from PIL import Image
a=Image.open(sys.argv[1]).convert('RGB'); b=Image.open(sys.argv[2]).convert('RGB')
x,y,w,h=map(int,sys.argv[3:7])
n=0
for yy in range(y+4,y+h-4):
    for xx in range(x+4,x+w-h):
        if a.getpixel((xx,yy))!=b.getpixel((xx,yy)): n+=1
print(n)
PY
)
    num "BILD: pixels that differ in the field between dots and plain text" "$D1" gt 40
fi
# QUICK ACCESS at the bottom right (Justin: "like Windows -- network,
# power, the time"): three things in the corner, none of them a Tab stop
# (the chain above already proves that), each answering a click.
NET=$(rect_of 2 3); POW=$(rect_of 2 4)
# a torn report line: the two icons are neighbours of the same size
if [ -z "$POW" ] && [ -n "$NET" ]; then
    POW="id=? kind=2 x=$(( $(fld "$NET" x) + $(fld "$NET" w) + 4 )) y=$(fld "$NET" y) w=$(fld "$NET" w) h=$(fld "$NET" h)"
fi
UHR=$(grep -aoE "^glogin: rect id=[0-9]+ kind=1 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$D/serial.txt" | awk -F'[ =]' '{ if ($8 > 900 && $10 > 650) print }' | head -1)
info "clock: $UHR"; info "network: $NET"; info "power: $POW"
if [ -n "$UHR" ] && [ "$(fld "$NET" x)" -gt 900 ] 2>/dev/null && [ "$(fld "$POW" y)" -gt 650 ] 2>/dev/null && [ "$(fld "$POW" y)" -lt 712 ] 2>/dev/null; then
    ok "clock, network and power sit in the bottom right corner (above the taskbar strip)"
else
    bad "the quick access is not in the bottom right corner"
fi
zeig $(( $(fld "$NET" x) + 16 )) $(( $(fld "$NET" y) + 16 )); klick
grep -aq 'glogin: schnell=1' "$D/serial.txt" && ok "a click on the network icon opens the network text" \
    || bad "'glogin: schnell=1' missing"
mon "screendump $D/netz.ppm" "sleep 1"; png "$D/netz.ppm" "$BEL/netz.png"
zeig $(( $(fld "$POW" x) + 16 )) $(( $(fld "$POW" y) + 16 )); klick
grep -aq 'glogin: schnell=2' "$D/serial.txt" && ok "a click on the power icon offers 'Herunterfahren' and 'Neu starten'" \
    || bad "'glogin: schnell=2' missing"
mon "screendump $D/strom.ppm" "sleep 1"; png "$D/strom.ppm" "$BEL/strom.png"
klick
grep -aq 'glogin: schnell=0' "$D/serial.txt" && ok "a second click closes it again (nothing is switched off)" \
    || bad "'glogin: schnell=0' missing"
grep -aq 'glogin: energie' "$D/serial.txt" && bad "GEGENPROBE: the power icon alone switched something" \
    || ok "GEGENPROBE: the icon alone switches nothing off"

# NO COPYING OUT: Ctrl+A, Ctrl+C in the password field ...
zeig $(( $(fld "$PW" x) + 20 )) $(( $(fld "$PW" y) + 10 ))
klick
mon "sendkey ctrl-a" "sleep 0.3" "sendkey ctrl-c" "sleep 0.5"
# 1. A MOUSE CLICK ON A BUTTON: "Anderer Benutzer" opens the name field
zeig $(( $(fld "$OTHER" x) + 40 )) $(( $(fld "$OTHER" y) + 12 ))
klick
grep -aq 'glogin: anderer benutzer' "$D/serial.txt" \
    && ok "a MOUSE click on 'Anderer Benutzer' is taken" \
    || bad "'glogin: anderer benutzer' missing -- the click did not arrive"
LAST=$(foci | tail -1 | grep -oE 'kind=[0-9]+')
[ "$LAST" = "kind=4" ] && ok "the name field has the focus now" || bad "focus after 'other user': $LAST"
# ... and Ctrl+V in the name field: if the password had been copied, the
# name would become "abcjustin" and the login below would be rejected.
mon "sendkey ctrl-v" "sleep 0.5" "screendump $D/other.ppm" "sleep 1"
png "$D/other.ppm" "$BEL/other.png"
mon "sendkey j" "sendkey u" "sendkey s" "sendkey t" "sendkey i" "sendkey n" "sleep 0.3" "sendkey ret" "sleep 1"
mon "sendkey ctrl-a" "sendkey backspace" "sleep 0.3"
for c in s t a r t k e n n w o r t; do mon "sendkey $c"; done
sleep 1
# the buttons moved (the name label went, the name field came); glogin
# reports its widgets again after that -- the LAST report counts
# (a report line can be torn -- so also from the password field, which the
# button follows at the same distance as before)
BN=$(grep -aoE 'rect id='"$BTNID"' kind=2 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$D/serial.txt" | tail -1)
PN=$(grep -aoE 'rect id='"$PWID"' kind=4 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+' "$D/serial.txt" | tail -1)
ABST=$(( $(fld "$BTN" y) - $(fld "$PW" y) ))
BY1=$(fld "$BN" y); BY2=$(( $(fld "$PN" y) + ABST ))
[ "${BY1:-0}" -gt "$BY2" ] && BY2=$BY1
BXY=$(( BY2 + 12 ))
info "Anmelden now at y=$BY2 ($BN / $PN)"
zeig $(( $(fld "$BN" x) + 40 )) "$BXY"
klick
sleep 12
if grep -aq 'glogin: angemeldet als justin' "$D/serial.txt"; then
    ok "name typed, password typed, MOUSE click on Anmelden: logged in as justin"
else
    bad "'glogin: angemeldet als justin' missing (button at y=${BXY:-?})"
    info "$(grep -a 'glogin: ab\|glogin: angem' "$D/serial.txt" | tail -2)"
fi
if grep -aq 'glogin: abgewiesen' "$D/serial.txt"; then
    bad "GEGENPROBE: an attempt was rejected -- the password was pasted into the name?"
else
    ok "GEGENPROBE: nothing was pasted into the name field (no rejected attempt)"
fi
halt_vm

# ==================================================== B. PS/2 keyboard
kopf "B. the PS/2 keyboard and mouse of the 8042 (the status check loses no key)"
if boot ps2 ps2; then
    ok "the login screen is up"
    gpid
    PW=$(rect_of 4 1); PWID=$(fld "$PW" id)
    mon "sendkey x" "sleep 0.3" "sendkey y" "sleep 0.3" "sendkey z" "sleep 0.3" "sendkey q" "sleep 1"
    BTN=$(rect_of 2 1); OTHER=$(rect_of 2 2)
    K=""
    k=0
    for t in tab tab tab; do
        k=$((k + 1))
        mon "sendkey $t" "sleep 0.8" "screendump $D/tab$k.ppm" "sleep 0.8"
        r=$(ring "$D/tab$k.ppm"); [ -z "$r" ] && { sleep 1; r=$(ring "$D/tab$k.ppm"); }; K="$K$r "
    done
    W="$(fld "$BTN" id) $(fld "$OTHER" id) $PWID "
    [ "$K" = "$W" ] && ok "Tab: button, button, field, in the picture ($K)" \
        || bad "PS/2 Tab chain '$K', expected '$W'"
    EX=$(eyerect)
    ex=$(fld "$EX" x); ey=$(fld "$EX" y); ew=$(fld "$EX" w)
    if [ -z "$ex" ]; then   # its one line was torn -- the eye is the square at the right end
        ew=$(fld "$PW" h); ex=$(( $(fld "$PW" x) + $(fld "$PW" w) - ew )); ey=$(fld "$PW" y)
    fi
    zeig $((ex + ew / 2)) $((ey + ew / 2)); klick
    L=$(eyes | tail -1)
    [ "$L" = "wlib: eye id=$PWID shown=1 len=4" ] \
        && ok "four PS/2 keys, four characters, PS/2 mouse on the eye ($L)" \
        || bad "PS/2: '$L', expected 'wlib: eye id=$PWID shown=1 len=4'"
    halt_vm
else
    bad "PS/2: the login screen did not come up"
    halt_vm
fi

ende
