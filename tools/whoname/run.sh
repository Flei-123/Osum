#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/whoname/run.sh -- W-INPUTHANG gate: after signing in as justin, Settings and the start menu name the SESSION owner (justin), not
# the uid of the root-run taskbar family ("root"). Needs a build dir (osum.mb + root.img) of a UITRACE=1 personal image:
#   UITRACE=1 PARTTAB=mbr FS_BLOCKS=122880 IMAGE_ID=x bash tools/usbimg/build.sh <dir>; bash tools/whoname/run.sh <dir>
set -uo pipefail
cd "$(dirname "$0")/../.."
B=${1:?build dir (osum.mb + root.img, UITRACE=1)}
[ -f "$B/osum.mb" ] && [ -f "$B/root.img" ] || { echo "FAIL: $B/osum.mb or root.img missing"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OK=0; BAD=0
ok() { OK=$((OK+1)); echo "  OK    $1"; }
bad() { BAD=$((BAD+1)); echo "  FAIL  $1"; }
cp "$B/root.img" "$W/d.img"
KVM=(-accel tcg); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
mon() { printf '%s\n' "$1" | timeout 5 socat - "unix-connect:$W/mon" >/dev/null 2>&1; }
timeout 200 qemu-system-x86_64 "${KVM[@]}" -m 512 -kernel "$B/osum.mb" \
    -append "gfx fbres=1024x768 wm wig desk wmshell wmdauer herz anmeldung nosched noproc nofs lang=de uiscale=1" \
    -serial "file:$W/ser" -display none -no-reboot -device VGA,edid=on,xres=1024,yres=768,vgamem_mb=32 \
    -monitor "unix:$W/mon,server,nowait" -drive "file=$W/d.img,format=raw,if=ide,index=0" >/dev/null 2>&1 &
QP=$!
for _ in $(seq 1 90); do grep -qa 'glogin: bereit' "$W/ser" 2>/dev/null && break; sleep 1; done
sleep 6
for k in s t a r t k e n n w o r t ret; do mon "sendkey $k"; sleep 0.4; done
for _ in $(seq 1 60); do grep -qa 'glogin: desktop pid=' "$W/ser" 2>/dev/null && break; sleep 1; done
sleep 12
mon "sendkey meta_l"; sleep 3
for k in e i n s t e l l u n g e n ret; do mon "sendkey $k"; sleep 0.4; done
sleep 12
kill $QP 2>/dev/null; wait $QP 2>/dev/null
grep -qa 'glogin: uid=1000' "$W/ser" && ok "the desktop runs as uid 1000" || bad "no 'glogin: uid=1000'"
grep -qa 'launcher: uid=1000 user=justin' "$W/ser" && ok "start menu footer: justin" || bad "start menu footer is not justin"
grep -qa 'settings: who uid=1000 name=justin' "$W/ser" && ok "Settings 'logged in as': justin (session owner, not the process uid)" \
    || { bad "Settings does not name justin"; grep -a 'settings: who' "$W/ser" | head -2; }
echo "WHONAME: $OK passed, $BAD failed"
[ "$BAD" -eq 0 ]
