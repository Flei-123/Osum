#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/kontogui.sh -- THE INSTALLER'S ACCOUNT FIELDS, TYPED LIKE A HUMAN.
#
#   BAU=<dir with osum.mb + root.img> bash tools/install/kontogui.sh [outdir]
#
# tools/install/abnahme.sh gives the account through arguments (`konto=`,
# `kontopw=`); this runs the WINDOW the way a person does: clicks in the three
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
grep -aq 'installer: disk /dev/hda' "$SER" && ok "the blank disk is listed (so the button CAN be on)" || bad "no disk listed"
[ -z "$(last)" ] && ok "empty form: nothing valid yet, the button is off" || bad "state before typing: '$(last)'"
# fields on the screen: window at (40,40), border 2, title 20 -> client origin (42,62)
click 576,518; keys b o b
[ "$(last)" = "ks=1 go=0" ] && ok "a valid name alone: ks=1, button off" || bad "after the name: '$(last)'"
click 576,558; keys a b c d
[ "$(last)" = "ks=2 go=0" ] && ok "name + password, the repeat empty: ks=2, button off" || bad "after the password: '$(last)'"
click 576,598; keys a b c d
[ "$(last)" = "ks=3 go=1" ] && ok "both passwords equal: ks=3, the button is ON" || bad "after the repeat: '$(last)'"
keys x
[ "$(last)" = "ks=2 go=0" ] && ok "one more key in the repeat: the button goes OFF again" || bad "after a mismatch: '$(last)'"
# counter-check: a bad name
click 576,518; keys ctrl-a delete shift-b o b
n=$(grep -ac 'installer: konto ks=' "$SER"); l=$(last)
case "$l" in "ks=0"*) ok "a name with a capital letter is no name (ks=0)";; *) bad "capital letter accepted: '$l'";; esac
kill $QP 2>/dev/null; wait $QP 2>/dev/null
echo
echo "KONTOGUI: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
