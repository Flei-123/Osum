#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#   BAU=<dir with osum.mb + root.img> [GUI_NAME=justin] [GUI_PW=abcd] bash tools/install/guiaccount.sh [outdir]
#
# Types the account into the installer window like a person, clicks Install, waits for the
# end and reads /etc/passwd, /etc/shadow, /etc/group and /users from the OFS partition the
# installer wrote. The name typed must be the only account besides root.
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1
. tools/lib/qemu.sh
OUT=${1:-/tmp/guiaccount}
mkdir -p "$OUT"
BAU=${BAU:-}
GUI_NAME=${GUI_NAME:-justin}
GUI_PW=${GUI_PW:-abcd}
INSTALL_WAIT=${INSTALL_WAIT:-2400}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
if [ -z "$BAU" ]; then
    BAU="$OUT/bau"
    bash tools/usbimg/build.sh "$BAU" > "$OUT/bau.log" 2>&1 || { echo "build failed"; tail -5 "$OUT/bau.log"; exit 1; }
fi
DISK="$OUT/target.img"
rm -f "$DISK"
truncate -s 320M "$DISK"
SER="$OUT/serial.txt"; SOCK="$OUT/mon.sock"; rm -f "$SER" "$SOCK"
APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=3000 nosched noproc nofs lang=de uiscale=1 wigapp=/bin/installer"
timeout 3300 $QEMU_X86 -m 512 -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
    -serial "file:$SER" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$DISK,format=raw,if=ide,index=0" > "$OUT/qemu.log" 2>&1 &
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
typed() { local s=$1 i c; for ((i = 0; i < ${#s}; i++)); do c=${s:i:1}; keys "$c"; done; }
last() { grep -a 'installer: account ks=' "$SER" | tail -1 | sed 's/.*account //'; }
grep -aq 'installer: ready n=1' "$SER" && ok "installer window up, one disk" || { bad "no installer window"; tail -3 "$SER"; }
rect_of() { grep -aoE "installer: rect id=$1 kind=[0-9]+ x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$SER" | head -1; }
last_button() {
    grep -aoE "installer: rect id=[0-9]+ kind=2 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$SER" | tail -1 \
        | awk '{ split($5,a,"="); split($6,b,"="); split($7,c,"="); split($8,d,"="); printf "%d,%d", 42 + a[2] + c[2]/2, 62 + b[2] + d[2]/2 }'
}
nth_entry() {
    grep -aoE "installer: rect id=[0-9]+ kind=4 x=[0-9]+ y=[0-9]+ w=[0-9]+ h=[0-9]+" "$SER" | sed -n "${1}p" \
        | awk '{ split($5,a,"="); split($6,b,"="); split($7,c,"="); split($8,d,"="); printf "%d,%d", 42 + a[2] + c[2]/2, 62 + b[2] + d[2]/2 }'
}
F1=$(nth_entry 1); F2=$(nth_entry 2); F3=$(nth_entry 3)
click "$F1"; typed "$GUI_NAME"
click "$F2"; typed "$GUI_PW"
click "$F3"; typed "$GUI_PW"
[ "$(last)" = "ks=3 go=1" ] && ok "typed name '$GUI_NAME' + password: ks=3, button on" || bad "state after typing: '$(last)'"
GO=$(last_button)
[ -n "$GO" ] && ok "install button at $GO" || bad "no install button rect"
click "$GO"
i=0
while [ $i -lt 60 ] && ! grep -qa 'installer: ask=1' "$SER"; do sleep 1; i=$((i+1)); done
keys ret
i=0
while [ $i -lt 60 ] && ! grep -qa 'installer: ask=2' "$SER"; do sleep 1; i=$((i+1)); done
keys ret
i=0
while [ $i -lt "$INSTALL_WAIT" ]; do
    grep -qa 'installer: done\|installer: ERROR' "$SER" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 1; i=$((i+1))
done
sleep 3
grep -qa 'installer: done' "$SER" && ok "installer finished" || bad "installer did not finish: $(grep -a 'installer:' "$SER" | tail -2 | tr '\n' '|')"
grep -a 'installer: account=' "$SER" | tail -1 | sed 's/^/        /'
kill $QP 2>/dev/null; wait $QP 2>/dev/null
trap - EXIT
bash tools/install/accountcheck.sh "$DISK" "$OUT" "$GUI_NAME" "$GUI_PW" > "$OUT/check.log" 2>&1
rc=$?
cat "$OUT/check.log"
fail=$((fail+$(grep -c "^  FAIL" "$OUT/check.log")))
pass=$((pass+$(grep -c "^  OK" "$OUT/check.log")))
echo
echo "GUIACCOUNT: $pass passed, $fail failed"
[ "$fail" = 0 ] || exit 1
exit 0
