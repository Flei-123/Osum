#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/kontogui.sh -- THE INSTALLER'S ACCOUNT FIELDS, TYPED LIKE A HUMAN.
#
#   BAU=<dir with osum.mb + root.img> bash tools/install/kontogui.sh [outdir]
#
# tools/install/abnahme.sh gives the account through arguments (`account=`,
# `password=`); this runs the WINDOW the way a person does: clicks in the three
# fields, keys through the QEMU monitor, and reads what the installer says about
# its own state (`installer: konto ks=<n> go=<0|1>`):
#
#   ks 0 nothing valid, 1 the name is valid, 2 name + password valid, 3 and the
#   two passwords equal; go = whether the Install button is on.
#
#   1. a window with an empty form: the button is OFF (nothing was printed yet)
#   2. name `bob`            -> ks=1 go=0
#   3. password `abcd`       -> ks=2 go=0   (the repeat is still empty)
#   4. the repeat `abcd`     -> ks=3 go=1   (and only now the button is on)
#   5. one more key `x` in the repeat -> ks=2 go=0 again (the button goes off)
#   6. COUNTER-CHECK: a name with a capital letter or a blank is no name: ks stays 0
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
OUT=${1:-/tmp/kontogui}
mkdir -p "$OUT"
BAU=${BAU:-}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
if [ -z "$BAU" ]; then
    BAU="$OUT/bau"
    bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || { echo "build failed"; tail -5 "$OUT/bau.log"; exit 1; }
fi
dd if=/dev/zero of="$OUT/blank.img" bs=1M count=0 seek=320 status=none
SER="$OUT/serial.txt"; SOCK="$OUT/mon.sock"; rm -f "$SER" "$SOCK"
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=900 nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer"
timeout 600 $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$SER" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/blank.img,format=raw,if=ide,index=0" > "$OUT/qemu.log" 2>&1 &
QP=$!
trap 'kill $QP 2>/dev/null' EXIT
i=0
while [ $i -lt 600 ]; do
    grep -qa 'installer: ready' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i+1))
done
sleep 4
mon() { printf '%s\n' "$@" > "$OUT/m.txt"; python3 tools/wm/monitor.py "$SOCK" "$OUT/m.txt" > "$OUT/m.log" 2>&1; }
click() { python3 tools/themestore/click.py "$1" > "$OUT/c.txt"; python3 tools/wm/monitor.py "$SOCK" "$OUT/c.txt" > "$OUT/c.log" 2>&1; sleep 1; }
keys() { local k; for k in "$@"; do mon "sendkey $k"; sleep 0.35; done; sleep 1; }
last() { grep -a 'installer: konto ks=' "$SER" | tail -1 | sed 's/.*konto //'; }
grep -aq 'installer: ready' "$SER" && ok "the installer window is up" || { bad "no installer window"; tail -3 "$SER"; }
grep -aq 'installer: ready n=1' "$SER" && ok "one disk is listed (so the button CAN be on)" || bad "no disk listed"
[ -z "$(last)" ] && ok "empty form: nothing valid yet, the button is off" || bad "state before typing: '$(last)'"
# the three fields: the installer says where its rectangles are (`installer: rect
# ... kind=4`, canvas coordinates); the window sits at (40,40), border 2, title 20,
# so the client origin is (42,62)
rect_of() { grep -aoE "installer: rect id=[0-9]+ kind=4 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$SER" | sed -n "${1}p"; }
centre() { # n -> "x,y" on the screen
    local r; r=$(rect_of "$1")
    [ -n "$r" ] || { echo "0,0"; return; }
    echo "$r" | awk '{ split($5,a,"="); split($6,b,"="); split($7,c,"="); split($8,d,"="); printf "%d,%d", 42 + a[2] + c[2]/2, 62 + b[2] + d[2]/2 }'
}
F1=$(centre 1); F2=$(centre 2); F3=$(centre 3)
[ "$F1" != "0,0" ] && ok "the installer reports its three fields (name at $F1, password $F2, repeat $F3)" || bad "no field rectangles reported"
click "$F1"; keys b o b
[ "$(last)" = "ks=1 go=0" ] && ok "a valid name alone: ks=1, button off" || bad "after the name: '$(last)'"
click "$F2"; keys a b c d
[ "$(last)" = "ks=2 go=0" ] && ok "name + password, the repeat empty: ks=2, button off" || bad "after the password: '$(last)'"
click "$F3"; keys a b c d
[ "$(last)" = "ks=3 go=1" ] && ok "both passwords equal: ks=3, the button is ON" || bad "after the repeat: '$(last)'"
keys x
[ "$(last)" = "ks=2 go=0" ] && ok "one more key in the repeat: the button goes OFF again" || bad "after a mismatch: '$(last)'"
# counter-check: a bad name
click "$F1"; keys ctrl-a delete shift-b o b
n=$(grep -ac 'installer: konto ks=' "$SER"); l=$(last)
case "$l" in "ks=0"*) ok "a name with a capital letter is no name (ks=0)";; *) bad "capital letter accepted: '$l'";; esac
kill $QP 2>/dev/null; wait $QP 2>/dev/null
echo
echo "KONTOGUI: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
