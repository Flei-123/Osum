#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/inputlogin/run.sh -- the sign-in screen must take keyboard input (16.10.2026).
#
#   IMG=<personal image> [IMG_BAD=<older image that has the bug>] bash tools/inputlogin/run.sh
#
# Bug (boss, VirtualBox, image 5cd0425): at the sign-in screen the keys never reached the password field.
# Cause: kgui.shell_start() started /bin/sh for the window console, and since LCSH /bin/sh is busybox in the
# personal image -- busybox ash on the console tty froze the sign-in input. The window console shell is now
# /bin/osh when it exists (wm: console sh: line on the serial).
#   A  PS/2 keyboard + mouse, machine pc (PIIX3), 3 CPUs, BIOS        -> `glogin: angemeldet als`
#   B  usb-kbd + usb-tablet on xhci, machine pc, 3 CPUs               -> the same
#   C  usb-kbd + usb-tablet on xhci, machine q35                      -> the same
#   D  A: serial has `wm: console sh: /bin/osh`
#   E  counter-probe (IMG_BAD, A): the old image must NOT log in -- proves the gate sees the bug
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE=$(pwd)/tools/inputlogin
IMG=${IMG:?set IMG=<personal image>}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

boot() { # boot <img> <name> <qemu args...>  -> $TMPD/<name>.serial, prints RESULT line into $TMPD/<name>.res
    local img=$1 name=$2; shift 2
    local d="$TMPD/$name"; mkdir -p "$d"
    cp "$img" "$d/s.img"
    local off=$((2048*512))
    mcopy -o -i "$d/s.img@@$off" ::/limine.conf "$d/l.orig" || return 1
    python3 - "$d/l.orig" "$d/l.conf" <<'PY'
import sys
L=open(sys.argv[1]).read().splitlines()
st=[i for i,l in enumerate(L) if l.startswith('/') and not l.startswith('//')][0]
en=next((j for j in range(st+1,len(L)) if L[j].startswith('/')),len(L))
open(sys.argv[2],'w').write('timeout: 0\ndefault_entry: 1\n\n'+'\n'.join(L[st:en])+'\n')
PY
    mcopy -o -i "$d/s.img@@$off" "$d/l.conf" ::/limine.conf
    mcopy -o -i "$d/s.img@@$off" "$d/l.conf" ::/boot/limine.conf
    qemu-system-x86_64 -m 2048 -drive file="$d/s.img",format=raw,if=none,id=stick -device ide-hd,drive=stick \
        -nic user,model=e1000 -serial file:"$TMPD/$name.serial" -display none -no-reboot \
        -monitor unix:"$d/mon",server,nowait "$@" &
    local qp=$!
    python3 -I "$HERE/drive.py" "$d/mon" "$TMPD/$name.serial" 150 > "$TMPD/$name.res" 2>&1
    kill $qp 2>/dev/null; wait $qp 2>/dev/null
    rm -f "$d/s.img"
}
accel=()
[ -w /dev/kvm ] && accel=(-accel kvm -cpu host)

boot "$IMG" A "${accel[@]}" -smp 3 -M pc -vga std &
boot "$IMG" B "${accel[@]}" -smp 3 -M pc -vga std -device qemu-xhci -device usb-kbd -device usb-tablet &
boot "$IMG" C "${accel[@]}" -smp 3 -M q35 -vga std -device qemu-xhci -device usb-kbd -device usb-tablet &
if [ -n "${IMG_BAD:-}" ]; then
    boot "$IMG_BAD" E "${accel[@]}" -smp 3 -M pc -vga std &
fi
wait
for n in A B C; do
    r=$(cat "$TMPD/$n.res" 2>/dev/null)
    case "$r" in *"login=1"*) ok "$n: typed password reaches the sign-in screen ($r)";; *) bad "$n: login failed ($r)";; esac
done
if grep -aq 'wm: console sh: /bin/osh' "$TMPD/A.serial"; then ok "D: window console shell is /bin/osh"
elif grep -aq 'wm: console sh: /bin/sh' "$TMPD/A.serial"; then ok "D: window console shell is /bin/sh (image without busybox sh)"
else bad "D: no 'wm: console sh:' line"; fi
if [ -n "${IMG_BAD:-}" ]; then
    r=$(cat "$TMPD/E.res" 2>/dev/null)
    case "$r" in *"login=0"*"ready=1"*) ok "E: counter-probe, old image does not log in ($r)";; *) bad "E: counter-probe did not show the bug ($r)";; esac
fi
echo "inputlogin: $pass ok / $fail fail"
[ "$fail" = 0 ]
