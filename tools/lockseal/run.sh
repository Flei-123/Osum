#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/lockseal/run.sh -- r382: THE LOCK SCREEN CANNOT BE WALKED AROUND.
#
#   bash tools/lockseal/run.sh [<workdir>]
#   KROOT=/path/to/other/tree bash tools/lockseal/run.sh   # counter-proof:
#       the KERNEL comes from that tree (e.g. an old main), the programs
#       from this one. The run must then FAIL.
#
# What stands behind the lock screen: the window "A11Y controls" of
# `a11ydemo` (a scene tree with the names Save, Add note, Hello tree ...),
# a tiling table (Alt+Tab = next window, Alt+Q = close window, F11 = full
# screen) and a root program (`a11ydemo lockprobe`) that tries everything a
# program can try. The host presses keys, clicks and takes photos.
#
# Measured:
#   1. screen        the photo shows the lock screen, not the window behind
#                    (the window's rectangle differs from the photo before the
#                    lock), and the photos before and after the attacks match
#   2. tree          a node of the window behind the lock reads as EMPTY
#                    (role 0): none of its names is readable; the lock screen's
#                    own nodes are
#   3. events        no a11y event about an emptied node
#   4. window table  root's list shows the lock screen only (no title, no id
#                    of the window behind)
#   5. keys          Alt+Tab, Alt+Q, F11 are dropped ("wm: hot gesperrt"), no
#                    focus change, no "wm: hot getan=1", the window is still
#                    there after the unlock
#   6. mouse         a click at the place of the window behind does not raise
#                    or focus it
#   7. hijack        a program that calls "be the locker" (op 4) and then "open"
#                    (op 2) gets -EPERM and the lock stays
#   8. syscall       tiling actions "close" and "next window" through the
#                    syscall are refused while locked
#   9. unlock        the right password still opens it, and then everything is
#                    visible again (so the seal does not just break the system)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"
KROOT=${KROOT:-$ROOT}

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

if [ -n "${1:-}" ]; then TMPD=$1; mkdir -p "$TMPD"; else TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT; fi
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep a11ydemo lock tiling"
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'
    echo "LOCKSEAL: $pass passed, $fail failed"; exit 1
fi
if (cd "$KROOT" && FIRNLIB="$KROOT/lib" ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0) > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds (from $KROOT)"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "LOCKSEAL: $pass passed, $fail failed"; exit 1
fi

# the account: root with the password geheim12
python3 - "$TMPD" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\n" % rec)
PY
cat > "$TMPD/tiling.conf" <<'EOS'
bind mod+tab next-window
bind mod+q close
bind f11 fullscreen
EOS
cat > "$TMPD/g.sh" <<'EOS'
tiling load /t/tiling.conf
a11ydemo set on 1
a11ydemo &
sleep 4
echo ==PRE==
a11ydemo lockprobe safe
echo ==PRE-DONE==
lock &
sleep 8
echo ==LOCKED==
a11ydemo lockprobe
echo ==LOCKED-DONE==
sleep 50
echo ==AFTER==
a11ydemo lockprobe
echo ==AFTER-DONE==
sleep 40
echo ==UNLOCKED==
a11ydemo lockprobe safe
echo ==FERTIG==
EOS

A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/ /etc/
   "/etc/shadow=$TMPD/shadow" "/t/g.sh=$TMPD/g.sh" "/t/tiling.conf=$TMPD/tiling.conf")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
A+=("/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "LOCKSEAL: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot, lock, attack =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 400 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
    -append "gfx disp wm wmdauer wmshell tile osum vfs script=sh /t/g.sh;exit" \
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
shot() { python3 tools/gfx/screenshot.py "$SOCK" "$1" 8 > /dev/null 2>&1; }
klick() { # x y
    python3 tools/themestore/click.py "$1,$2" > "$TMPD/c.txt" 2>/dev/null
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/c.txt" > /dev/null 2>&1
    sleep 1.5
}
keys() { # monitor lines
    printf '%s\n' "$@" > "$TMPD/keys.txt"
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/keys.txt" 0.4 > /dev/null 2>&1
    sleep 1
}
if waitfor "==PRE-DONE==" 200; then
    shot "$TMPD/pre.ppm"
else
    bad "the guest did not reach the lock"
fi
if waitfor "==LOCKED-DONE==" 120; then
    sleep 2
    shot "$TMPD/b.ppm"
    keys "sendkey alt-tab" "sendkey alt-tab" "sendkey alt-q" "sendkey f11" "sendkey f12" \
         "sendkey alt-f4" "sendkey ctrl-alt-delete" "sendkey meta_l-d" "sendkey meta_l-tab" "sendkey alt-esc"
    # the window behind the lock sat at 60,60 (a11ydemo): click into it
    klick 200 72
    klick 200 300
    shot "$TMPD/c.ppm"
else
    bad "the guest did not finish the locked probe"
fi
if waitfor "==AFTER-DONE==" 150; then
    # the password, only now: the probe above must still have seen the lock
    keys "sendkey g" "sendkey e" "sendkey h" "sendkey e" "sendkey i" "sendkey m" "sendkey 1" "sendkey 2" "sendkey ret"
    sleep 6
    keys "sendkey g" "sendkey e" "sendkey h" "sendkey e" "sendkey i" "sendkey m" "sendkey 1" "sendkey 2" "sendkey ret"
else
    bad "the guest did not reach the second probe"
fi
waitfor "==FERTIG==" 120 || note "no FERTIG before the time limit"
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
G="$TMPD/ser.klar"
for q in "$TMPD"/*.ppm; do
    [ -s "$q" ] && python3 -c "from PIL import Image; Image.open('$q').save('${q%.ppm}.png')" 2>/dev/null
done

echo "== 3. before the lock (baseline) =="
part "$G" PRE PRE-DONE > "$TMPD/p_pre.txt"
has "$TMPD/p_pre.txt" "name=Save" "unlocked: the tree has the names of the window (Save)"
has "$TMPD/p_pre.txt" "title=A11Y controls" "unlocked: the window table lists the window"
VID=$(grep -aoE 'win slot=[0-9]+ id=[0-9]+ title=A11Y controls' "$TMPD/p_pre.txt" | head -1 | sed -E 's/.* id=([0-9]+) .*/\1/')
note "the window behind the lock has id ${VID:-?}"

grep -qaE 'claim rc=-[1-9][0-9]* unlock rc=[1-9][0-9]* state after=0' "$TMPD/p_pre.txt" \
    && ok "unlocked: a program cannot register as the locker in advance (op 4 refused: it would own the NEXT lock)" \
    || bad "unlocked: hijack line: $(grep -a 'claim rc' "$TMPD/p_pre.txt" | head -1)"

echo "== 4. locked: tree, events, window table =="
part "$G" LOCKED LOCKED-DONE > "$TMPD/p_l1.txt"
part "$G" AFTER AFTER-DONE > "$TMPD/p_l2.txt"
for P in "$TMPD/p_l1.txt" "$TMPD/p_l2.txt"; do
    case "$P" in *l1*) W="at the lock";; *) W="after the attacks";; esac
    for nm in "name=Save" "name=Add note" "name=Hello tree" "name=Remember me" "name=Accessibility" "name=Password" "name=Disabled"; do
        hasnot "$P" "$nm" "$W: the tree does not give '${nm#name=}'"
    done
    grep -qaE 'name=.*(Entsperren|Kennwort)' "$P" && ok "$W: the lock screen's own nodes are readable (the seal is no blindfold for the locker)" || bad "$W: no node of the lock screen readable"
    grep -qaE 'events seen=[0-9]+ leaked=0' "$P" && ok "$W: no a11y event about a node behind the lock" || bad "$W: events: $(grep -a 'events seen' "$P" | head -1)"
    hasnot "$P" "title=A11Y controls" "$W: the window table does not list the window behind the lock"
    if [ -n "$VID" ]; then
        grep -qaE " id=$VID " "$P" && bad "$W: the table has the id $VID" || ok "$W: ... nor its id"
    fi
    has "$P" "title=Gesperrt" "$W: the table lists the lock screen"
done

echo "== 5. locked: the hijack and the syscalls =="
for P in "$TMPD/p_l1.txt" "$TMPD/p_l2.txt"; do
    case "$P" in *l1*) W="at the lock";; *) W="after the attacks";; esac
    grep -qaE 'claim rc=-[0-9]+ unlock rc=[0-9]+ state after=1' "$P" \
        && ok "$W: 'be the locker' and 'open' by a root program: refused, still locked" \
        || bad "$W: hijack line: $(grep -a 'claim rc' "$P" | head -1)"
    grep -qaE 'tile close rc=-[0-9]+ next rc=-[0-9]+' "$P" && ok "$W: tiling 'close' and 'next window' through the syscall are refused" || bad "$W: tiling line: $(grep -a 'tile close' "$P" | head -1)"
done

echo "== 6. the keys and the mouse =="
LK=$(awk '/==LOCKED-DONE==/{f=1} /==UNLOCKED==/{f=0} f' "$G")
if [ -n "$VID" ]; then
    n=$(printf '%s\n' "$LK" | grep -aEc "wm: fokus id=$VID( |$)")
    [ "$n" = 0 ] && ok "no focus change to the window behind the lock while locked: $n" || bad "the window behind the lock got the focus $n times"
fi
n=$(printf '%s\n' "$LK" | grep -ac 'wm: hot gesperrt')
[ "$n" -ge 3 ] && ok "shortcuts reached the window server and were dropped: $n" || bad "shortcut lines dropped: $n (expected >= 3)"
n=$(printf '%s\n' "$LK" | grep -ac 'wm: hot getan=1')
[ "$n" = 0 ] && ok "no shortcut did anything while locked (getan=1: $n)" || bad "shortcuts that DID something while locked: $n"

echo "== 7. the photo =="
python3 - "$TMPD" <<'PY' > "$TMPD/shot.txt" 2>&1
import sys
from PIL import Image
from collections import Counter
d = sys.argv[1]
def load(n):
    try: return Image.open("%s/%s.png" % (d, n)).convert("RGB")
    except Exception as e: return None
a, b, c = load("pre"), load("b"), load("c")
if not (a and b and c):
    print("PHOTO missing", bool(a), bool(b), bool(c)); sys.exit(0)
box = (80, 100, 460, 330)   # the middle of the window at 60,60 (420x300)
def dominant(x, box):
    raw = x.crop(box).tobytes()
    px = [raw[i:i+3] for i in range(0, len(raw), 3)]
    return 100.0 * Counter(px).most_common(1)[0][1] / len(px)
def same(x, y):
    bx, by = x.tobytes(), y.tobytes()
    n = len(bx) // 3
    diff = sum(1 for i in range(0, len(bx), 3)
               if abs(bx[i]-by[i]) + abs(bx[i+1]-by[i+1]) + abs(bx[i+2]-by[i+2]) > 24)
    return 100.0 - 100.0 * diff / n
print("WINDOW_BEFORE %.1f" % dominant(a, box))
print("WINDOW_LOCKED %.1f" % dominant(b, box))
print("LOCKED_VS_ATTACKED %.1f" % same(b, c))
PY
sed 's/^/        /' "$TMPD/shot.txt"
wb=$(grep -a WINDOW_BEFORE "$TMPD/shot.txt" | awk '{print $2}')
wl=$(grep -a WINDOW_LOCKED "$TMPD/shot.txt" | awk '{print $2}')
bc=$(grep -a LOCKED_VS_ATTACKED "$TMPD/shot.txt" | awk '{print $2}')
if [ -n "$wb" ] && awk -v v="$wb" 'BEGIN{exit !(v<97)}'; then ok "before the lock the window's area is full of content (the biggest single colour: $wb %)"; else bad "before the lock the window's area looks empty ('$wb' %)"; fi
if [ -n "$wl" ] && awk -v v="$wl" 'BEGIN{exit !(v>99.5)}'; then ok "at the lock the same area is ONE colour ($wl %): nothing of the window shows through"; else bad "at the lock the window's area is not empty ('$wl' % one colour)"; fi
if [ -n "$bc" ] && awk -v v="$bc" 'BEGIN{exit !(v>97)}'; then ok "the locked screen after the attacks looks as before them ($bc % equal)"; else bad "the locked screen changed during the attacks ('$bc' % equal)"; fi

echo "== 8. the password still opens it =="
has "$G" "sperre: aufgesperrt" "the right password unlocks"
part "$G" UNLOCKED FERTIG > "$TMPD/p_un.txt"
has "$TMPD/p_un.txt" "name=Save" "unlocked again: the window's names are readable again"
has "$TMPD/p_un.txt" "title=A11Y controls" "... and the window is in the table (nothing was closed behind the lock)"

echo; echo "LOCKSEAL: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
