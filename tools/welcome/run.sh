#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/welcome/run.sh -- E3: THE WELCOME WINDOW (/bin/welcome), MEASURED.
#
#   /root/jarvis/bin/heavy bash tools/welcome/run.sh
#
# Part A, guest shell (no display): the switch /etc/welcome.conf
#   - no file          -> `welcome status` says show=nein (a missing file means NO)
#   - `welcome show on`  -> the file holds show=ja, status says ja
#   - `welcome show off` -> the file holds show=nein, status says nein
#   - `welcome -a` with show=nein exits silently (rc 0, no window line)
#   - COUNTER-PROBE: `welcome -a` with show=ja TRIES to open the window
#     (no display in this guest -> "welcome: no surface"); so the silent exit above
#     is the switch and not a broken program
#   - bad arguments -> usage, rc 2
# Part B, audit machine with a display: /etc/welcome.conf (show=ja) in the image,
# the desktop starts `/bin/welcome -a` by itself:
#   - "welcome: ready", the window has a check box and two buttons (3 rects)
#   (the GUI toggle is NOT measured yet -- see the note near the end)
# Static: the string keys exist in de + en, the bundle is in the stick list.
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' is there and should not be" || ok "$3"; }
part() { awk -v a="==$2==" -v b="==$3==" 'index($0,a){f=1;next} index($0,b){f=0} f' "$1"; }
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
# ---- static
for l in de en; do
    n=$(grep -c '^welcome\.\(title\|head\|t1\|t2\|t3\|show\|sett\|close\) = ' locale/$l/messages)
    [ "$n" = 8 ] && ok "locale $l: 8 welcome.* keys" || bad "locale $l: $n of 8 welcome.* keys"
done
grep -q 'privacy welcome"}' tools/usbimg/build.sh && ok "usbimg PROGS has welcome" || bad "usbimg PROGS"
grep -q '/apps/welcome.osp/start' tools/usbimg/build.sh && ok "usbimg PFLICHT has the bundle" || bad "usbimg PFLICHT"
grep -q 'welcome_start()' kernel/user/desktop.fi && ok "desktop starts the welcome window" || bad "desktop hook"
grep -q 'welcome.conf' kernel/user/instkonto.fi && ok "installer writes /etc/welcome.conf" || bad "installer hook"
# ---- part A
mkdir -p "$TMPD/bin"
PROGS="sh cat echo welcome"
if bash tools/sync/build.sh "$TMPD/bin" 0 $PROGS > "$TMPD/b.txt" 2>&1; then ok "welcome builds"; else bad "build"; head -20 "$TMPD/b.txt"; echo "WELCOME: $pass passed, $fail failed"; exit 1; fi
if ./tools/build-kernel.sh "$TMPD/k0.img" --stufe 0 > "$TMPD/k.txt" 2>&1; then ok "kernel builds"; else bad "kernel"; tail -5 "$TMPD/k.txt"; echo "WELCOME: $pass passed, $fail failed"; exit 1; fi
cat > "$TMPD/s.sh" <<'EOS'
echo ==ST0==
welcome status
echo ==ON==
welcome show on
cat /etc/welcome.conf
welcome status
echo ==OFF==
welcome show off
cat /etc/welcome.conf
welcome status
echo ==AOFF==
welcome -a
echo rc=$?
echo ==AON==
welcome show on
welcome -a
echo ==USE==
welcome frob
echo ==END==
EOS
python3 tools/osum/mkfs.py build "$TMPD/d.img" 20000 /lib/ \
    "/lib/mono.ttf=assets/osum-mono.ttf" "/lib/sans.ttf=assets/osum-sans.ttf" \
    /bin/ /t/ /tmp/ /proc/ /dev/ /system/ /etc/ /var/ \
    $(for p in $PROGS; do echo "/bin/$p=$TMPD/bin/$p.elf"; done) \
    "/t/s.sh=$TMPD/s.sh" > "$TMPD/mkfs.txt" 2>&1 || tail -3 "$TMPD/mkfs.txt"
timeout 150 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 \
    -kernel "$TMPD/k0.img" -m 512 \
    -append "osum vfs nokbd script=sh /t/s.sh;exit" \
    -serial "file:$TMPD/o.txt" -display none -no-reboot \
    -drive "file=$TMPD/d.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$TMPD/o.txt" > "$TMPD/o.klar"
for s in "ST0 ON" "ON OFF" "OFF AOFF" "AOFF AON" "AON USE" "USE END"; do set -- $s; part "$TMPD/o.klar" "$1" "$2" > "$TMPD/$1.txt"; done
has "$TMPD/ST0.txt" "welcome: show=nein" "no file -> status nein"
has "$TMPD/ON.txt" "show=ja" "show on: the file holds show=ja"
has "$TMPD/ON.txt" "welcome: show=ja" "show on: status says ja"
has "$TMPD/OFF.txt" "show=nein" "show off: the file holds show=nein"
has "$TMPD/OFF.txt" "welcome: show=nein" "show off: status says nein"
hasnot "$TMPD/AOFF.txt" "welcome: ready" "-a with show=nein opens no window"
hasnot "$TMPD/AOFF.txt" "welcome: no surface" "-a with show=nein does not even try"
has "$TMPD/AOFF.txt" "rc=0" "-a with show=nein exits with 0"
has "$TMPD/AON.txt" "welcome: no surface" "COUNTER-PROBE: -a with show=ja tries to open the window"
has "$TMPD/USE.txt" "usage: welcome" "bad argument: usage text"
# ---- part B
W=$(mktemp -d); trap 'rm -rf "$TMPD" "$W" "$W-build" "$W-drehbuch.txt" "$W.log" "$W-welcome.conf"' EXIT
printf 'show=ja\n' > "$W-welcome.conf"
export DESIGNBUILD="$W-build"
export AUDIT_MKFS_EXTRA="/etc/ /etc/welcome.conf=$W-welcome.conf"
{
  echo "warte 14"
  echo "foto 00-welcome"
} > "$W-drehbuch.txt"
bash tools/design/audit.sh "$W" accel=kvm uitrace=yes halt=300 \
    progs="desktop taskbar settings launcher explorer edit sh echo ls cat theme welcome" \
    drehbuch="$W-drehbuch.txt" > "$W.log" 2>&1
S="$W/serial.txt"
has "$S" "welcome: ready" "audit machine: the desktop started the welcome window by itself"
n=$(grep -ac '^welcome: rect ' "$S" 2>/dev/null; true)
[ "$n" = 3 ] && ok "window has 3 touchable controls (check box + 2 buttons)" || bad "controls reported: $n"
# NOT CHECKED (open, r849 note): toggling the check box by key/click in the GUI. A bare `space` does not
# reach the box (focus is not on it); the switch itself is covered by part A (`welcome show on|off`).
c=$(grep -acE 'ABSTURZ|EXCEPTION' "$S" 2>/dev/null; true)
[ "$c" = 0 ] && ok "no crash" || bad "crash lines: $c"
echo "WELCOME: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
