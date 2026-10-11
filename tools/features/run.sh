#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/features/run.sh -- EVERYDAY FEATURES, VM gate (docs/FEATURES-STAND.md).
#
#   bash tools/features/run.sh        (start it through /root/jarvis/bin/heavy)
#
# 1. NOTIFICATION CENTRE (kernel/user/notifc.fi): two `notify` posts -> the bell node is in the bar's
#    a11y tree (act=taskbar.notifications) -> pressing it opens the card with both rows, newest first
#    -> Tab + Enter on the "Clear all" button empties it (`notifc: clear n=2`, `open n=0`) -> a third
#    post while the card stands grows the list (n=1: the base line works) -> the bell closes it.
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
PROGS="sh ls cat echo sleep orientbus act axd notify"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 \
   && (cd "$BARROOT" && FIRNLIB="$BARROOT/lib" bash tools/sync/build.sh "$TMPD/barbin" 0 taskbar) > "$TMPD/b2.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs and the task bar (from $BARROOT)"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" "$TMPD/b2.txt" | sed 's/^/        /'
    echo "FEATURES: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "FEATURES: $pass passed, $fail failed"; exit 1
fi

cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
taskbar &
sleep 30
notify first message
notify second message
sleep 4
echo ==F-TREE==
act call a11y.tree window=Taskbar
echo ==F-OPEN==
act call a11y.press action=taskbar.notifications window=Taskbar
sleep 4
echo ==F-KEYS==
sleep 25
echo ==F-AFTER==
notify third message
sleep 4
echo ==F-CLOSE==
act call a11y.press action=taskbar.notifications window=Taskbar
sleep 4
echo ==F-END==
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
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "FEATURES: $pass passed, $fail failed"; exit 1; }

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
if waitfor "==F-KEYS==" 1500; then
    sleep 3
    keys "sendkey tab"
    keys "sendkey ret"
else
    bad "the guest did not reach the keyboard part"
fi
waitfor "==FERTIG==" 600
python3 tools/gfx/screenshot.py "$SOCK" "$TMPD/features.ppm" 8 > /dev/null 2>&1
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
perl -0pi -e 's/wm: fen i=[^\n]*? tka=\d+\r?\n//g' "$TMPD/ser.klar"
G="$TMPD/ser.klar"
[ -n "${FEATURES_OUT:-}" ] && { mkdir -p "$FEATURES_OUT"; cp "$G" "$TMPD/features.ppm" "$FEATURES_OUT/" 2>/dev/null; }

echo "== 3. notification centre =="
part "$G" F-TREE F-OPEN > "$TMPD/t1.txt"
grep -qaF "act=taskbar.notifications" "$TMPD/t1.txt" && ok "the bell is a node of the bar with act=taskbar.notifications" || bad "no bell node with act=taskbar.notifications"
grep -qaE '"Notifications"' "$TMPD/t1.txt" && ok "the bell node is named 'Notifications'" || bad "the bell node has no name"
grep -qaF "taskbar: no notifc host" "$G" && bad "the bar had no room for the card" || ok "the card has its window (no 'no notifc host')"
o1=$(grep -a 'notifc: open n=' "$G" | head -1)
echo "$o1" | grep -qaF "n=2" && ok "pressing the bell opens the card with 2 rows" || bad "first open is not n=2: '$o1'"
r0=$(grep -a 'notifc: row 0 ' "$G" | head -1); r1=$(grep -a 'notifc: row 1 ' "$G" | head -1)
echo "$r0" | grep -qaF "second message" && ok "row 0 is the newest (second message)" || bad "row 0 wrong: '$r0'"
echo "$r1" | grep -qaF "first message" && ok "row 1 is the older one (first message)" || bad "row 1 wrong: '$r1'"
grep -qaF "notifc: clear n=2" "$G" && ok "Tab + Enter on 'Clear all' marked 2 entries read" || bad "no 'notifc: clear n=2'"
grep -aq 'notifc: open n=0' "$G" && ok "after clearing the list is empty" || bad "no empty list after clearing"
o3=$(grep -a 'notifc: open n=1' "$G" | tail -1)
[ -n "$o3" ] && ok "a post while the card stands shows one row (the old two stay cleared)" || bad "no 'open n=1' after the third post"
grep -a 'notifc: row 0 ' "$G" | tail -1 | grep -qaF "third message" && ok "that row is the third message" || bad "the last row 0 is not the third message"
grep -qaF "notifc: shut bell" "$G" && ok "the bell closes the card again" || bad "no 'notifc: shut bell'"
[ -s "$TMPD/features.ppm" ] && ok "screenshot taken ($(stat -c%s "$TMPD/features.ppm") octets)" || bad "no screenshot"

echo; echo "FEATURES: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
