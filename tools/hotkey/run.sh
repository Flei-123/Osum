#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotkey/run.sh -- W-S3 gate (docs/HOTKEYS.md): global hotkeys, portal model. Run through /root/jarvis/bin/heavy.
# One guest: window server + bus + a.jarvismini + hotkeyd (wmplug plugin). QEMU `sendkey ctrl-alt-j` -> toggle=1, again -> 0.
# Counter-proofs: no helper -> nothing; app without right `hotkey` -> refused; double binding -> conflict line; plain Alt key -> refused.
# Lock screen (r382 seal): while the screen is locked the shortcut is dropped by the window server (`wm: hot gesperrt`), the helper
# hears nothing and the toggle state stays; after the unlock the same shortcut works again (toggle sequence 1,0,1 -- NOT 1,0,1,0).
# Serial parsing is TOLERANT: kernel lines (elf: / wm: / wmplug:) that other processes write in the middle of a helper line are cut
# out of the log before the helper lines are searched (the raw log is used for the kernel lines themselves).
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="$(pwd)/lib"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
mkdir -p "$TMPD/bin"
PROGS="sh ls cat echo sleep orientbus act jarvismini wmplug hotkeyd apprights lock"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1 || { bad "programs do not build"; tail -8 "$TMPD/b.txt"; exit 1; }
./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1 || { bad "kernel does not build"; tail -5 "$TMPD/k.txt"; exit 1; }
# config: 1 good line, 1 double of it, 1 key without right (app "norite"), 1 plain Alt key
cat > "$TMPD/hotkeys.conf" <<'EOC'
ctrl+alt+j jarvismini.toggle
ctrl+alt+j jarvismini.toggle
ctrl+alt+k norite.toggle
alt+j jarvismini.toggle
EOC
python3 - "$TMPD" <<'PYEOF'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\n" % rec)
PYEOF
printf '# /etc/theme.conf\nscheme=day\nmode=light\naccent=\nshape=classic\n' > "$TMPD/theme.conf"
cat > "$TMPD/g.sh" <<'EOC'
orientbus serve 0 &
sleep -m 300
jarvismini serve 0 &
sleep 1
apprights set jarvismini hotkey
echo ==NOHELPER==
sleep 2
echo ==HELPER==
wmplug enable hotkey
sleep 3
echo ==READY==
sleep 12
echo ==AFTER==
lock &
sleep 8
echo ==LOCKED==
sleep 14
echo ==LOCKED2==
sleep 30
echo ==UNLOCKED==
sleep 14
echo ==FERTIG==
EOC
A=(build "$TMPD/disk.img" 32768 /lib/ "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" /bin/ /t/ /tmp/ /var/ /var/log/
   /etc/ /etc/actions.d/ /etc/orientbus/ "/etc/actions.d/jarvismini.actions=etc/actions.d/jarvismini.actions"
   "/etc/orientbus/policy=etc/orientbus/policy" "/etc/hotkeys.conf=$TMPD/hotkeys.conf" "/etc/wmplug.conf=etc/wmplug.conf" "/t/g.sh=$TMPD/g.sh"
   "/etc/shadow=$TMPD/shadow" "/etc/theme.conf=$TMPD/theme.conf" /etc/schemas/)
[ -f assets/osum-icons.ttf ] && A+=("/lib/icons.ttf=assets/osum-icons.ttf")
[ -f assets/osum-sans-bold.ttf ] && A+=("/lib/bold.ttf=assets/osum-sans-bold.ttf")
for sc in assets/schemes/*.scheme; do A+=("/etc/schemas/$(basename "$sc" .scheme)=$sc"); done
for p in $PROGS; do A+=("/bin/$p=$TMPD/bin/$p.elf"); done
python3 tools/osum/mkfs.py "${A[@]}" > "$TMPD/mkfs.txt" 2>&1 || { bad "mkfs"; tail -3 "$TMPD/mkfs.txt"; exit 1; }
SOCK="$TMPD/mon.sock"
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
timeout 240 qemu-system-x86_64 "${ACC[@]}" -kernel "$TMPD/k0.img" -m 512 \
    -append "gfx disp wm wmdauer wmshell osum vfs bus wmplug script=sh /t/g.sh;exit" \
    -serial "file:$TMPD/ser.txt" -display none -no-reboot -vga std -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$TMPD/disk.img,format=raw,if=ide,index=0" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/q.txt" 2>&1 &
QPID=$!
waitfor() { local i=0; while [ $i -lt $(( $2 * 5 )) ]; do grep -qaF -- "$1" "$TMPD/ser.txt" 2>/dev/null && return 0; kill -0 "$QPID" 2>/dev/null || return 1; sleep 0.2; i=$((i+1)); done; return 1; }
keys() { printf '%s\n' "$@" > "$TMPD/keys.txt"; python3 tools/wm/monitor.py "$SOCK" "$TMPD/keys.txt" 0.3 > /dev/null 2>&1; sleep 1.5; }
waitfor "==NOHELPER==" 120 && keys "sendkey ctrl-alt-j"      # no helper yet: nothing may happen
PW=("sendkey g" "sendkey e" "sendkey h" "sendkey e" "sendkey i" "sendkey m" "sendkey 1" "sendkey 2" "sendkey ret")
waitfor "==READY==" 120 && { keys "sendkey ctrl-alt-j"; keys "sendkey ctrl-alt-j"; keys "sendkey ctrl-alt-k"; }
waitfor "==LOCKED==" 120 && keys "sendkey ctrl-alt-j"      # locked: the shortcut must be dropped
if waitfor "==LOCKED2==" 60; then
    keys "${PW[@]}"
    waitfor "sperre: aufgesperrt" 8 || { keys "${PW[@]}"; }
fi
waitfor "==UNLOCKED==" 90 && keys "sendkey ctrl-alt-j"     # unlocked again: it works again
waitfor "==FERTIG==" 90 || echo "  (no FERTIG)"
printf 'quit\n' | socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1; wait "$QPID" 2>/dev/null
R="$TMPD/ser.klar"; tr -cd '\11\12\15\40-\176' < "$TMPD/ser.txt" > "$R"
# tolerant copy: cut whole kernel lines that were written in the middle of a helper line
G="$TMPD/ser.norm"
python3 - "$R" "$G" <<'PYEOF'
import re, sys
t = open(sys.argv[1], errors="replace").read()
t = re.sub(r"(elf: (?:seg|start) [^\n]*|wm: [^\n]*|wmplug: [^\n]*)\n", "", t)
open(sys.argv[2], "w").write(t)
PYEOF
[ -n "${HOTKEY_KEEP:-}" ] && cp "$R" "$HOTKEY_KEEP"
echo "== checks =="
has "$G" "hotkeyd: bound ctrl+alt+j jarvismini.toggle" "binding made for an app that holds the right"
has "$G" "hotkeyd: conflict ctrl+alt+j jarvismini.toggle held-by=jarvismini.toggle" "double binding is reported, not overwritten"
has "$G" "hotkeyd: refused ctrl+alt+k norite.toggle reason=no-right" "app without the right hotkey is refused"
has "$G" "hotkeyd: refused alt+j jarvismini.toggle reason=system-key" "plain Alt key (system) is refused"
AFT=$(awk 'index($0,"==AFTER=="){exit} {print}' "$G")
seq=$(printf '%s\n' "$AFT" | grep -ao "jarvismini: toggle=[01]" | sed 's/.*=//' | tr -d '\n')
[ "$seq" = 10 ] && ok "ctrl-alt-j -> toggle=1, again -> toggle=0" || bad "toggle sequence before the lock '$seq', want 10"
n=$(printf '%s\n' "$AFT" | grep -ac "jarvismini: toggle="); [ "${n:-0}" = 2 ] && ok "exactly 2 toggles before the lock (key before the helper and the unbound ctrl-alt-k did nothing)" || bad "toggle count before the lock $n, want 2"
hasnot "$G" "hotkeyd: fired norite" "the unbound key fired nothing"
echo "== lock screen =="
LK=$(awk 'index($0,"==LOCKED=="){f=1;next} index($0,"==UNLOCKED=="){f=0} f' "$G")
RK=$(awk 'index($0,"==LOCKED=="){f=1;next} index($0,"==UNLOCKED=="){f=0} f' "$R")
n=$(printf '%s\n' "$RK" | grep -ac "wm: hot gesperrt c=106 mod=5"); [ "${n:-0}" -ge 1 ] && ok "locked: the window server dropped ctrl-alt-j (wm: hot gesperrt, $n x)" || bad "locked: no 'wm: hot gesperrt c=106 mod=5' line"
n=$(printf '%s\n' "$RK" | grep -ac "wm: plughot"); [ "$n" = 0 ] && ok "locked: no plugin heard the key (plughot: $n)" || bad "locked: the plugin got the key ($n x)"
n=$(printf '%s\n' "$LK" | grep -ac "jarvismini: toggle="); [ "$n" = 0 ] && ok "locked: the toggle did not move (toggle lines: $n)" || bad "locked: the toggle moved ($n lines)"
n=$(printf '%s\n' "$LK" | grep -ac "hotkeyd: fired"); [ "$n" = 0 ] && ok "locked: the helper fired nothing" || bad "locked: hotkeyd fired $n x"
has "$R" "sperre: aufgesperrt" "the password unlocks"
seq=$(grep -ao "jarvismini: toggle=[01]" "$G" | sed 's/.*=//' | tr -d '\n')
[ "$seq" = 101 ] && ok "after the unlock the shortcut works again: toggle sequence 1,0,1 (the locked press did not count)" || bad "toggle sequence over the whole run '$seq', want 101"
echo "HOTKEY: $pass passed, $fail failed"; [ "$fail" = 0 ]
