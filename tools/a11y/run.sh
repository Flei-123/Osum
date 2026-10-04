#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/a11y/run.sh -- ROUND A11Y-2: THE ACCESSIBILITY TREE, MEASURED.
#
#   bash tools/a11y/run.sh [workdir]
#
# One Osum guest with the window server, the action bus, the provider axd
# and the measuring app a11ydemo (installed as an app bundle, so its kernel
# label is `app:a11ydemo`). What is measured (docs/A11Y.md 8):
#
#   1. S-007: the tree comes from wlib with no work in the app -- roles,
#      names, places, the bus action ids; the kernel's self test.
#   2. The password field: the canary word GEHEIMNIS7 is in the field (the
#      app says length and checksum, never the word) and appears in NO
#      export, NO log, NO kernel dump -- anywhere on the serial line, in
#      the bus's audit log. Both locks: wlib sends no value, the kernel
#      forces the value of a forged password node to 0 and counts it.
#   3. The rights: no read, no event, no press without the kernel right;
#      a node for a window that is not the caller's is refused; the right
#      falls at exec.
#   4. AB-021: the tree over the bus -- the user reads it, Jarvis must dry
#      run first and is then asked; with a grant it reads; a press goes to
#      the app (its own log says so), a disabled button, a user's own
#      window (no app label) are refused by the kernel.
#   5. S-008: sticky keys (Shift alone, then Tab = backwards), the
#      magnifier (every panel pixel is the source pixel, twice enlarged --
#      checked in the screenshot against the kernel's own numbers; it
#      follows the FOCUS after Tab), high contrast (the contrast scheme,
#      ratio measured). Photos into docs/shots/a11y/ with KEEP_SHOTS=1.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="${FIRNLIB:-$ROOT/lib}"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note(){ printf '        %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }

TMPD=${1:-$(mktemp -d)}
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep orientbus act axd a11ydemo"

echo "== 1. build =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
python3 tools/a11y/fields.py && ok "the node packing agrees in kernel, wlib and axd" || bad "the node packing differs (tools/a11y/fields.py)"
python3 tools/actionbus/manifest.py check etc/actions.d/a11y.actions > "$TMPD/lint.txt" 2>&1 \
    && ok "host reader takes the manifest ($(cut -d' ' -f3- "$TMPD/lint.txt"))" || bad "manifest: $(cat "$TMPD/lint.txt")"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then
    ok "firnc0 builds $(echo $PROGS | wc -w) programs"
else
    bad "the programs do not build"; tail -15 "$TMPD/b.txt" | sed 's/^/        /'
    echo "A11Y: $pass passed, $fail failed"; exit 1
fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then
    ok "the kernel builds"
else
    bad "the kernel does not build"; tail -5 "$TMPD/k.txt" | sed 's/^/        /'
    echo "A11Y: $pass passed, $fail failed"; exit 1
fi

cat > "$TMPD/g.sh" <<'EOS'
orientbus serve 0 &
sleep -m 300
axd serve 0 &
sleep 1
/apps/a11ydemo.prog/start &
sleep 3
a11ydemo plain &
sleep 3
echo ==A-STATUS==
act call a11y.status
echo ==A-TREE==
act call a11y.tree window=controls
echo ==A-FIND==
act call a11y.find role=password
act call a11y.find role=button window=controls
echo ==A-JARVIS==
act call a11y.tree --as jarvis
act call a11y.tree window=controls --dry --as jarvis
act call a11y.tree window=controls --as jarvis
# AB-004: the parked read also stands in the window server's trusted
# dialog, which takes every real key while it is up. The human says no on
# the shell; that takes the dialog down (else it would eat the keys of 6.)
sleep 2
act reject last
echo ==A-REJECTED==
act grant jarvis a11y.tree write 60
act call a11y.tree window=controls --dry --as jarvis
act call a11y.tree window=controls --as jarvis
echo ==A-PRESS==
act call a11y.press name=Save window=controls --dry
act call a11y.press name=Save window=controls
sleep 1
act call a11y.press action=notes.add window=controls
sleep 1
act call a11y.press name=Save
act call a11y.press "name=Remember me" window=controls
sleep 1
echo ==A-JPRESS==
act call a11y.press name=Save window=controls --dry --as jarvis
act call a11y.press name=Save window=controls --as jarvis
act confirm last
sleep 1
echo ==A-REFUSE==
act call a11y.press name=Disabled window=controls
act call a11y.press name=Save window=plain
act call a11y.press name=Nothing
echo ==A-FORGE==
a11ydemo forge
sleep 1
echo ==A-KEYS==
a11ydemo set sticky 1
a11ydemo set mag 1
sleep 20
echo ==A-DUMP==
a11ydemo dump
act call a11y.status
echo ==A-HIGH==
a11ydemo set high 1
sleep 4
a11ydemo theme
sleep 8
echo ==A-LOG==
cat /var/log/orientbus.log
echo ==A-STAT==
act stat
act stop
echo ==FERTIG==
EOS

A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf"
   "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/ /apps/ /apps/a11ydemo.prog/
   "/etc/actions.d/a11y.actions=etc/actions.d/a11y.actions"
   "/etc/orientbus/policy=etc/orientbus/policy"
   "/apps/a11ydemo.prog/start=$TMPD/bin/a11ydemo.elf"
   "/t/g.sh=$TMPD/g.sh")
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
A+=("/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
for s in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$s" .scheme)=$s"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 \
    && ok "the disk: $(stat -c%s "$TMPD/disk.img") octets" \
    || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt" | sed 's/^/        /'; echo "A11Y: $pass passed, $fail failed"; exit 1; }

echo "== 2. boot: window server, bus, axd, the app =="
SOCK="$TMPD/mon.sock"; rm -f "$SOCK"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 300 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 768 \
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
shot() { python3 tools/gfx/screenshot.py "$SOCK" "$1" 5 > /dev/null 2>&1; }
klick() { # x y
    python3 tools/themestore/click.py "$1,$2" > "$TMPD/c.txt" 2>/dev/null
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/c.txt" > /dev/null 2>&1
    sleep 1.5
}
keys() { # sendkey lines
    printf '%s\n' "$@" > "$TMPD/keys.txt"
    python3 tools/wm/monitor.py "$SOCK" "$TMPD/keys.txt" 0.3 > /dev/null 2>&1
    sleep 1
}
if waitfor "==A-KEYS==" 150; then
    sleep 3
    # the app's window gets the keyboard: a click on its title bar
    klick 200 70
    # three Tabs forward, then Shift ALONE (sticky: it latches) and one
    # Tab -- that one must go BACKWARDS
    keys "sendkey tab" "sendkey tab" "sendkey tab"
    sleep 1
    keys "sendkey shift" "sendkey tab"
    sleep 3
    shot "$TMPD/mag-focus.ppm"
else
    bad "the script did not reach the key part"
fi
if waitfor "==A-HIGH==" 60; then sleep 10; shot "$TMPD/contrast.ppm"; fi
waitfor "==FERTIG==" 90 || note "no FERTIG before the time limit"
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1
wait "$QPID" 2>/dev/null
tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$TMPD/ser.klar"
# The window server's window list (`wm: fen ... tka=N`, one line per
# window, printed on the measuring key tile.A_SAY) shares the serial line with
# the programs. It can land in the MIDDLE of an a11ydemo line
# ("a11ydemo: noright read=wm: fen ... tka=81<nl>1 event=1 ..."), and the
# check then fails on a line the program printed correctly. No check here
# reads the window list, so it is cut out, which rejoins the split line.
perl -0pi -e 's/wm: fen i=[^\n]*? tka=\d+\r?\n//g' "$TMPD/ser.klar"
G="$TMPD/ser.klar"
for q in "$TMPD"/*.ppm; do
    [ -s "$q" ] && python3 -c "from PIL import Image; Image.open('$q').save('${q%.ppm}.png')" 2>/dev/null
done

echo "== 3. the tree (S-007) =="
has "$G" "ax: selftest 6 / 6" "the kernel store's self test: 6 of 6"
grep -qaE 'axd: serving a.a11y rights=3 on=0' "$G" && ok "axd: root gave itself read+act; nothing recorded yet (on=0)" || bad "axd start: $(grep -a 'axd: serving' "$G" | head -1)"
grep -qaE 'axd: recording nodes=[1-9][0-9]*' "$G" && ok "the first question switched recording on: $(grep -aoE 'axd: recording nodes=[0-9]+' "$G" | head -1)" || bad "no recording after the first question"
has "$G" "orientbus: provider a11y bound" "axd is bound as the provider of a11y.*"
grep -qaE 'a11ydemo: secret len=10 sum=[0-9]+' "$G" && ok "the password field holds the 10-letter canary (the app says length and checksum only)" || bad "no secret line from the app"
part "$G" A-TREE A-FIND > "$TMPD/p.txt"
has "$TMPD/p.txt" '=window win' "the listing has the window node"
has "$TMPD/p.txt" '"A11Y controls"' "... named by its title"
has "$TMPD/p.txt" '"Save" act=notes.save' "... the button Save carries its bus action notes.save"
has "$TMPD/p.txt" '"Add note" act=notes.add' "... and Add note carries notes.add"
has "$TMPD/p.txt" '=check' "... a check box"
has "$TMPD/p.txt" '"Hello tree"' "... an entry with its text"
has "$TMPD/p.txt" '"Accessibility"' "... a label"
has "$TMPD/p.txt" '=list' "... a list"
grep -qaE '=password win[0-9]+ [0-9]+,[0-9]+ [0-9]+x[0-9]+ [a-z,]*protected[a-z,]* "Password"' "$TMPD/p.txt" \
    && ok "the password field: role password, state protected, only its set name" || bad "no protected password node: $(grep -a password "$TMPD/p.txt" | head -1)"
grep -a '=password' "$TMPD/p.txt" | grep -qa 'value=' && bad "the password node has a value in the export" || ok "... and no value in the export"
grep -a '"Disabled"' "$TMPD/p.txt" | grep -qa 'enabled' && bad "the disabled button claims 'enabled'" || ok "the disabled button is not 'enabled'"
part "$G" A-FIND A-JARVIS > "$TMPD/p.txt"
grep -qa 'count=2' "$TMPD/p.txt" && ok "a11y.find role=password: one per window of the app (two instances)" || bad "find password: $(head -4 "$TMPD/p.txt" | tr '\n' ' ')"

echo "== 4. the canary, the locks, the rights =="
n=$(grep -ac 'GEHEIMNIS7' "$TMPD/ser.txt")
[ "$n" = 0 ] && ok "the canary GEHEIMNIS7 appears NOWHERE on the serial line (exports, bus log, kernel dump): $n" || bad "the canary appears $n times"
n2=$(grep -ac 'HEIMNIS' "$TMPD/ser.txt")
[ "$n2" = 0 ] && ok "... not even in part (HEIMNIS): $n2" || bad "a part of the canary appears $n2 times"
grep -qaE 'ax: node [0-9]+ role=6 state=[0-9]+ .* value=0 act= name=Password' "$G" \
    && ok "the kernel dump: the password node holds value 0 and only its name" || bad "kernel dump of the password node: $(grep -a 'role=6' "$G" | head -1)"
grep -qaE 'ax: nodes=[0-9]+ .* leaks=1 ' "$G" && ok "the kernel counted exactly one leak attempt (the forged one) -- wlib sent none" || bad "leaks: $(grep -a 'ax: nodes=' "$G" | tail -1)"
grep -qa 'a11ydemo: noright read=1 event=1 press=1 mine=0' "$G" \
    && ok "without the kernel right: read, event and press are -EPERM" || bad "no-right line: $(grep -a 'noright' "$G" | head -1)"
grep -qaE 'a11ydemo: forge begin=0 taken=0 end=0 leaks=0 foreign=3' "$G" \
    && ok "a forged push for windows that are not the caller's: nothing taken, all three counted foreign" || bad "forge: $(grep -a 'forge begin' "$G" | head -1)"
grep -qaE 'a11ydemo: forge2 begin=0 taken=2 end=2 leaks=1' "$G" \
    && ok "the KERNEL lock: a password node WITH a value through the caller's own window is taken with value 0 and counted" \
    || bad "forge2: $(grep -a 'forge2' "$G" | head -1)"
has "$G" "a11ydemo: granted mine=3" "root granted itself both rights ..."
has "$G" "a11ydemo: after exec mine=0" "... and after exec the rights are gone"

echo "== 5. over the bus (AB-021) =="
part "$G" A-JARVIS A-PRESS > "$TMPD/p.txt"
has "$TMPD/p.txt" "err dry_run_first a11y.tree" "Jarvis reading the tree without a dry run is refused (dryfirst jarvis)"
has "$TMPD/p.txt" "decision=ask" "... the dry run says: ask (the screen is not Jarvis' to read)"
grep -qa '^confirm ' "$TMPD/p.txt" && ok "... the real read is parked for the human" || bad "Jarvis' read was not parked"
grep -qaF '"Save" act=notes.save' "$TMPD/p.txt" && ok "with 'act grant jarvis a11y.tree write 60' Jarvis reads it" || bad "Jarvis did not get the tree after the grant"
part "$G" A-JARVIS A-PRESS > "$TMPD/p.txt"
has "$TMPD/p.txt" "wm: trusted dialog up no=" "... the parked read is put to the person in the window server's trusted dialog (AB-004)"
has "$TMPD/p.txt" "wm: trusted dialog down no=" "... which 'act reject' on the shell takes down again"
part "$G" A-PRESS A-JPRESS > "$TMPD/p.txt"
has "$TMPD/p.txt" 'would=a11y.press' "a dry press is answered by the broker, nothing reaches the app ..."
has "$TMPD/p.txt" 'decision=allow' "... the user's decision: allow"
n=$(grep -ac 'pressed=1' "$TMPD/p.txt")
[ "$n" -ge 3 ] && ok "the user pressed Save, notes.add (by its action id) and the check box: $n" || bad "presses: $n"
has "$TMPD/p.txt" "err ambiguous count=2" "'Save' in two windows: ambiguous, nothing pressed"
grep -qaE 'a11ydemo: fired id=[0-9]+ kind=2 val=0 presses=1' "$G" && ok "the APP got the press (its own log: fired, kind button)" || bad "the app did not see the press"
grep -qaE 'a11ydemo: fired id=[0-9]+ kind=3 val=1 presses=3' "$G" && ok "... the check box toggled to 1 in the app" || bad "check box: $(grep -a 'kind=3' "$G" | head -1)"
part "$G" A-JPRESS A-REFUSE > "$TMPD/p.txt"
has "$TMPD/p.txt" "decision=ask" "Jarvis' press: the dry run says ask"
grep -qa 'pressed=1' "$TMPD/p.txt" && ok "... and after the human's yes it is pressed" || bad "Jarvis' press after the yes: $(tail -3 "$TMPD/p.txt" | tr '\n' ' ')"
part "$G" A-REFUSE A-FORGE > "$TMPD/p.txt"
n=$(grep -ac 'err refused kernel_errno=13' "$TMPD/p.txt")
[ "$n" -ge 2 ] && ok "the kernel refuses a disabled button and a user's own window (no app label): $n" || bad "refusals: $n -- $(tr '\n' ' ' < "$TMPD/p.txt" | cut -c1-200)"
grep -qa 'ax: press node=[0-9]* wid=[0-9]* slot=[0-9]* refuse=2' "$G" && ok "... reason 2 (not enabled)" || bad "no refusal reason 2"
grep -qa 'ax: press node=[0-9]* wid=[0-9]* slot=[0-9]* refuse=7' "$G" && ok "... reason 7 (not an app's window)" || bad "no refusal reason 7"
has "$TMPD/p.txt" "err no_such_control" "a name nobody has: an honest error"
part "$G" A-LOG A-STAT > "$TMPD/p.txt"
grep -qa 'client=jarvis verb=call action=a11y.tree' "$TMPD/p.txt" && ok "the audit log has Jarvis' reads of the tree" || bad "no audit line for Jarvis' tree read"
grep -qa 'action=a11y.press' "$TMPD/p.txt" && ok "... and the presses" || bad "no audit line for a press"

echo "== 6. S-008: sticky keys, magnifier, high contrast =="
grep -qa 'kbd: sticky latch=1' "$G" && ok "Shift alone latched" || bad "Shift did not latch"
python3 - "$G" <<'PY' && ok "the Tab after Shift-alone went BACKWARDS (focus returned to an earlier control)" || bad "sticky Shift+Tab: focus did not go back"
import re, sys
t = open(sys.argv[1], errors='replace').read()
i = t.find('kbd: sticky latch=1')
before = [int(x) for x in re.findall(r'a11ydemo: focus id=(\d+)', t[:i])]
after = [int(x) for x in re.findall(r'a11ydemo: focus id=(\d+)', t[i:])]
print("focus before", before[-3:], "after", after[:2])
sys.exit(0 if before and after and after[0] < before[-1] else 1)
PY
python3 - "$G" "$TMPD/mag-focus.png" > "$TMPD/mag.txt" 2>&1 <<'PY' && ok "magnifier: $(cat "$TMPD/mag.txt")" || bad "magnifier: $(cat "$TMPD/mag.txt")"
import re, sys
from PIL import Image
t = open(sys.argv[1], errors='replace').read()
m = re.search(r'ax: mag px=(\d+) sx=(\d+) sy=(\d+) cx=(\d+) cy=(\d+) mode=(\d+) frames=(\d+)', t)
if not m:
    print("no 'ax: mag' line"); sys.exit(1)
px, sx, sy, cx, cy, mode, frames = map(int, m.groups())
im = Image.open(sys.argv[2]).convert('RGB')
bad = 0; n = 0
for r in range(4, 146):
    for c in range(4, 196):
        n += 1
        if im.getpixel((px + c, r)) != im.getpixel((sx + c // 2, sy + r // 2)):
            bad += 1
print(f"{n - bad}/{n} panel pixels equal their source (2x); panel x={px}, source {sx},{sy}, mode={mode} (1=focus), frames={frames}")
sys.exit(0 if bad * 100 <= n and mode == 1 else 1)
PY
grep -qaE 'a11ydemo: theme fg=[0-9]+ bg=[0-9]+ ratio100=([0-9]{4}) high=1' "$G" \
    && ok "high contrast: $(grep -aoE 'ratio100=[0-9]+' "$G" | tail -1) (WCAG ratio x100)" || bad "high contrast: $(grep -a 'theme fg' "$G" | tail -1)"
grep -qaE 'panic|EXCEPTION|#PF|#GP' "$G" && bad "a panic or exception" || ok "no panic, no exception"
if [ "${KEEP_SHOTS:-0}" = 1 ]; then
    mkdir -p docs/shots/a11y
    for f in mag-focus contrast; do [ -s "$TMPD/$f.png" ] && cp "$TMPD/$f.png" docs/shots/a11y/; done
fi
for f in mag-focus contrast; do
    [ -s "$TMPD/$f.png" ] && ok "photo: $TMPD/$f.png" || bad "no photo $f"
done
rm -f "$TMPD/disk.img" "$TMPD"/*.ppm
echo "A11Y: $pass passed, $fail failed"
[ "$fail" = 0 ]
