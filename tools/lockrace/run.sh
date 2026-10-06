#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/lockrace/run.sh -- r389: THE LOCKER IS KILLED, AND NOBODY TAKES THE LOCK OVER.
#
#   bash tools/lockrace/run.sh [<workdir>]
#   KROOT=/path/to/other/tree bash tools/lockrace/run.sh   # counter-proof: the
#       KERNEL comes from that tree (e.g. an old main), the programs from this
#       one. The run must then FAIL (a child wins the lock).
#
# While the screen is locked a root program (`a11ydemo lockrace`) kills the
# locker (`lock`). The kernel restarts it (`kgui.sperre_wache`, every 32nd
# turn), but until then the lock names the dead locker's task SLOT, and the
# zombie reaper frees that slot within ~16 turns. A process that lands in the
# slot used to pass `osum_sperre` op 4 ("be the locker": slot matches, the
# old pid is gone) and could then open the lock with op 2, no password.
#
# The probe, for two seconds after the kill: bursts of six `lockclaim`
# children (each: op 4, and if that worked op 2), the window table read all the
# time (the victim window must never show), and the tick at which the lock
# screen is back.
#
# The first locker is started by the shell (`lock &`): its zombie stays in the table.
# So the probe kills it once first (`lockrace warm`) and races against the SECOND one,
# which the kernel started itself -- the real case, whose slot the reaper frees.
#
# Measured:
#   1. kill        the probe found and killed a live `lock`
#   2. race        children started: >= 20, children that became the locker: 0
#   3. table       the victim window ("A11Y controls") never showed in the table
#   4. still locked the lock is still on after the race (op 0 = 1)
#   5. restart     the kernel started a new locker ("sperre: Sperrer neu") and the lock
#                  screen is back within 7 s
#   6. after       a second probe: the tree gives nothing of the victim, the table has
#                  "Gesperrt" only, the hijack (op 4 / op 2) is refused
#   7. password    the right password still opens it afterwards
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
PROGS="sh ls cat echo sleep a11ydemo lock lockclaim"
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'
    echo "LOCKRACE: $pass passed, $fail failed"; exit 1
fi
if (cd "$KROOT" && FIRNLIB="$KROOT/lib" ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0) > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds (from $KROOT)"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "LOCKRACE: $pass passed, $fail failed"; exit 1
fi

python3 - "$TMPD" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\n" % rec)
PY
cat > "$TMPD/g.sh" <<'EOS'
a11ydemo set on 1
a11ydemo &
sleep 4
lock &
sleep 8
echo ==LOCKED==
a11ydemo lockprobe safe
echo ==LOCKED-DONE==
a11ydemo lockrace warm
sleep 3
echo ==RACE==
a11ydemo lockrace
echo ==RACE-DONE==
sleep 6
echo ==AFTER==
a11ydemo lockprobe
echo ==AFTER-DONE==
sleep 60
echo ==UNLOCKED==
a11ydemo lockprobe safe
echo ==FERTIG==
EOS
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/ /etc/
   "/etc/shadow=$TMPD/shadow" "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
A+=("/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "LOCKRACE: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot, lock, kill the locker =="
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
keys() { # monitor lines
    printf '%s\n' "$@" > "$TMPD/keys.txt"
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/keys.txt" 0.4 > /dev/null 2>&1
    sleep 1
}
waitfor "==LOCKED-DONE==" 240 || bad "the guest did not reach the lock"
waitfor "==RACE-DONE==" 120 || bad "the race probe did not finish"
if waitfor "==AFTER-DONE==" 120; then
    shot "$TMPD/after.ppm"
    keys "sendkey g" "sendkey e" "sendkey h" "sendkey e" "sendkey i" "sendkey m" "sendkey 1" "sendkey 2" "sendkey ret"
    sleep 6
    keys "sendkey g" "sendkey e" "sendkey h" "sendkey e" "sendkey i" "sendkey m" "sendkey 1" "sendkey 2" "sendkey ret"
else
    bad "the guest did not reach the probe after the race"
fi
waitfor "==FERTIG==" 150 || note "no FERTIG before the time limit"
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
G="$TMPD/ser.klar"
[ -s "$TMPD/after.ppm" ] && python3 -c "from PIL import Image; Image.open('$TMPD/after.ppm').save('$TMPD/after.png')" 2>/dev/null

echo "== 3. before the race =="
part "$G" LOCKED LOCKED-DONE > "$TMPD/p_pre.txt"
has "$TMPD/p_pre.txt" "title=Gesperrt" "the lock screen is up before the kill"

echo "== 4. the race =="
part "$G" RACE RACE-DONE > "$TMPD/p_race.txt"
R=$(grep -a 'lockrace killed pid=' "$TMPD/p_race.txt" | tail -1)
note "$R"
[ -n "$R" ] && ok "the probe found a live locker and killed it" || bad "the probe did not kill a locker: $(grep -a "lockrace" "$TMPD/p_race.txt" | head -2)"
n=$(printf '%s' "$R" | grep -oE 'children=[0-9]+' | sed 's/.*=//')
[ -n "$n" ] && [ "$n" -ge 20 ] && ok "children that tried to take the lock over: $n" || bad "too few children ('$n', wanted >= 20)"
w=$(printf '%s' "$R" | grep -oE 'won=[0-9]+' | sed 's/.*=//')
[ "$w" = 0 ] && ok "none of them became the locker (won=0)" || bad "a child became the locker: won='$w'"
hasnot "$TMPD/p_race.txt" "lockclaim: WON" "nobody opened the lock without the password"
v=$(printf '%s' "$R" | grep -oE 'victim_seen=[0-9]+' | sed 's/.*=//')
[ "$v" = 0 ] && ok "the victim window never showed in the window table (it was read all the time)" || bad "the victim window showed $v times"
st=$(printf '%s' "$R" | grep -oE 'state=[0-9]+' | sed 's/.*=//')
[ "$st" = 1 ] && ok "after the race the lock is still on" || bad "the lock is not on after the race (state='$st')"
b=$(printf '%s' "$R" | grep -oE 'back_after=[0-9]+' | sed 's/.*=//')
if [ -n "$b" ] && [ "$b" -gt 0 ] && [ "$b" -le 700 ]; then ok "the lock screen is back $b ticks after the kill (<= 700, the new locker is loaded from the disk)"; else bad "the lock screen came back after '$b' ticks (0 = never, wanted 1..700)"; fi
n=$(grep -ac 'sperre: Sperrer neu' "$G")
[ "$n" -ge 1 ] && ok "the kernel started a new locker ($n x 'sperre: Sperrer neu')" || bad "no 'sperre: Sperrer neu'"

echo "== 5. after the race =="
part "$G" AFTER AFTER-DONE > "$TMPD/p_after.txt"
for nm in "name=Save" "name=Add note" "name=Hello tree" "name=Remember me" "name=Password"; do
    hasnot "$TMPD/p_after.txt" "$nm" "the tree does not give '${nm#name=}'"
done
hasnot "$TMPD/p_after.txt" "title=A11Y controls" "the table does not list the victim"
has "$TMPD/p_after.txt" "title=Gesperrt" "the table lists the lock screen"
grep -qaE 'claim rc=-[0-9]+ unlock rc=[0-9]+ state after=1' "$TMPD/p_after.txt" \
    && ok "'be the locker' and 'open' by a root program: refused, still locked" \
    || bad "hijack line: $(grep -a 'claim rc' "$TMPD/p_after.txt" | head -1)"
if [ -s "$TMPD/after.png" ]; then
    python3 - "$TMPD/after.png" <<'PY' > "$TMPD/shot.txt" 2>&1
import sys
from PIL import Image
from collections import Counter
x = Image.open(sys.argv[1]).convert("RGB")
raw = x.crop((80, 100, 460, 330)).tobytes()
px = [raw[i:i+3] for i in range(0, len(raw), 3)]
print("WINDOW_AFTER %.1f" % (100.0 * Counter(px).most_common(1)[0][1] / len(px)))
PY
    wa=$(grep -a WINDOW_AFTER "$TMPD/shot.txt" | awk '{print $2}')
    if [ -n "$wa" ] && awk -v v="$wa" 'BEGIN{exit !(v>99.5)}'; then ok "the photo after the race shows ONE colour where the victim stood ($wa %)"; else bad "the photo after the race is not empty where the victim stood ('$wa' %)"; fi
else
    bad "no photo after the race"
fi

echo "== 6. the password still opens it =="
has "$G" "sperre: aufgesperrt" "the right password unlocks"
part "$G" UNLOCKED FERTIG > "$TMPD/p_un.txt"
has "$TMPD/p_un.txt" "name=Save" "unlocked again: the window's names are readable"

echo; echo "LOCKRACE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
