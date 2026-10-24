#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/save.sh -- W-WLAN16a gate: the signed-in session user (uid 1000) can write /etc/wlan.conf.
#   bash tools/wlan/save.sh <build-dir> [old-build-dir]
# <build-dir> needs osum.mb + root.img (tools/usbimg/build.sh <dir>). With old-build-dir the same steps run on the old image:
# the checks marked [X] must then be RED (prints SAVE-GEGENPROBE: n/n red).
set -uo pipefail
cd "$(dirname "$0")/../.."
B=${1:?build dir}
GEG=0
[ -n "${2:-}" ] && { B=$2; GEG=1; }
[ -f "$B/osum.mb" ] && [ -f "$B/root.img" ] || { echo "FAIL: $B/osum.mb or root.img missing"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OK=0; BAD=0; XRED=0; XALL=0
ok() { OK=$((OK+1)); echo "  OK    $1"; }
bad() { BAD=$((BAD+1)); echo "  FAIL  $1"; }
xchk() {
    XALL=$((XALL+1))
    if [ "$GEG" = 1 ]; then
        if [ "$1" != 0 ]; then XRED=$((XRED+1)); echo "  RED   $2 (as wanted with the old image)"; else echo "  GREEN $2 (unexpected with the old image)"; fi
    else
        if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi
    fi
}
KVM=(-accel tcg); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
mon() { printf '%s\n' "$1" | timeout 5 socat - "unix-connect:$W/mon" >/dev/null 2>&1; }
keys() { local k; for k in "$@"; do mon "sendkey $k"; sleep 0.4; done; }
waitfor() { local i; for i in $(seq 1 "$2"); do grep -qa -- "$1" "$W/ser" 2>/dev/null && return 0; sleep 1; done; return 1; }
meta() {
    python3 -I - "$W/d.img" /etc/wlan.conf <<'PY'
import sys
sys.path.insert(0, "tools/osum")
import mkfs
fs = mkfs.load(sys.argv[1])
ino = fs.resolve(sys.argv[2]) if fs else 0
if not ino:
    print("absent")
else:
    mode, uid, gid = fs.get_meta(ino)
    size = fs.iget(ino, mkfs.I_SIZE)
    print("%o %d %d %s" % (mode, uid, gid, fs.read_at(ino, 0, size).decode("latin1").replace("\n", "|")))
PY
}
cp "$B/root.img" "$W/d.img"
timeout 300 qemu-system-x86_64 "${KVM[@]}" -m 512 -kernel "$B/osum.mb" \
    -append "gfx fbres=1024x768 wm wig desk wmshell wmdauer herz anmeldung nosched noproc nofs lang=de uiscale=1" \
    -serial "file:$W/ser" -display none -no-reboot -device VGA,edid=on,xres=1024,yres=768,vgamem_mb=32 \
    -monitor "unix:$W/mon,server,nowait" -drive "file=$W/d.img,format=raw,if=ide,index=0" >/dev/null 2>&1 &
QP=$!
waitfor 'glogin: bereit' 120; sleep 6
keys s t a r t k e n n w o r t ret
waitfor 'glogin: desktop pid=' 90; sleep 12
mon "sendkey meta_l"; sleep 3
keys t e r m i n a l ret
waitfor 'launcher: start /apps/terminal.osp/start pid=' 40; sleep 8
keys e c h o spc s s i d spc g a t e n e t spc shift-less spc shift-7 e t c shift-7 w l a n dot c o n f ret
sleep 2
keys s y n c ret
sleep 6
kill $QP 2>/dev/null; wait $QP 2>/dev/null
grep -aq 'glogin: uid=1000' "$W/ser" && ok "the desktop runs as uid 1000" || bad "no 'glogin: uid=1000'"
M=$(meta)
echo "  info  /etc/wlan.conf: $M"
case "$M" in absent) PRES=1 ;; *) PRES=0 ;; esac
xchk $PRES "[X] /etc/wlan.conf exists after sign-in"
case "$M" in "600 1000 "*) R=0 ;; *) R=1 ;; esac
xchk $R "[X] /etc/wlan.conf is mode 0600 owned by uid 1000"
case "$M" in *"ssid gatenet|"*) R=0 ;; *) R=1 ;; esac
xchk $R "[X] the session user wrote 'ssid gatenet' into /etc/wlan.conf from the terminal"
if [ "$GEG" = 1 ]; then
    echo "SAVE-GEGENPROBE: $XRED/$XALL red"
    [ "$XRED" -eq "$XALL" ]
else
    echo "SAVE: $OK passed, $BAD failed"
    [ "$BAD" -eq 0 ]
fi
