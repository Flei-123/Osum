#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
B=${1:?build dir (osum.mb + root.img, UITRACE=1)}
OLD=${2:-}
DIR=$B; COUNTER=0
[ -n "$OLD" ] && { DIR=$OLD; COUNTER=1; }
K="$DIR/osum.mb"
[ -f "$K" ] && [ -f "$DIR/root.img" ] || { echo "FAIL: $K or $DIR/root.img missing"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OK=0; BAD=0; RED=0; ALL=0
check() {
    ALL=$((ALL+1))
    if [ "$COUNTER" = 1 ]; then
        if [ "$1" != 0 ]; then RED=$((RED+1)); echo "  RED   $2 (as wanted with the old image)"; else echo "  GREEN $2 (unexpected with the old image)"; fi
    elif [ "$1" = 0 ]; then OK=$((OK+1)); echo "  OK    $2"; else BAD=$((BAD+1)); echo "  FAIL  $2"; fi
}
cp "$DIR/root.img" "$W/d.img"
KVM=(-accel tcg); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
mon() { printf '%s\n' "$1" | timeout 5 socat - "unix-connect:$W/mon" >/dev/null 2>&1; }
keys() { local k; for k in "$@"; do mon "sendkey $k"; sleep 0.4; done; }
timeout 330 qemu-system-x86_64 "${KVM[@]}" -m 512 -kernel "$K" \
    -append "gfx fbres=1024x768 wm wig desk wmshell wmdauer herz anmeldung nosched noproc nofs lang=de uiscale=1" \
    -serial "file:$W/ser" -display none -no-reboot -device VGA,edid=on,xres=1024,yres=768,vgamem_mb=32 \
    -monitor "unix:$W/mon,server,nowait" -drive "file=$W/d.img,format=raw,if=ide,index=0" >/dev/null 2>&1 &
QP=$!
count() { grep -ac -- "$1" "$W/ser" 2>/dev/null || true; }
waitfor() { local i; for i in $(seq 1 "$2"); do grep -qa -- "$1" "$W/ser" 2>/dev/null && return 0; sleep 1; done; return 1; }
waitfor 'glogin: ready' 120; sleep 6
keys s t a r t k e n n w o r t ret
waitfor 'glogin: desktop pid=' 90; sleep 12
ELEV0=$(count 'elevate: ready')
for t in 1 2 3; do
    keys esc; mon "sendkey meta_l"; sleep 3
    keys f i r e f o x ret
    waitfor 'launcher: start /apps/firefox.osp/start pid=' 25 && break
done
sleep 8
FP=$(grep -a 'launcher: start /apps/firefox.osp/start pid=' "$W/ser" | tail -1 | sed 's/.*pid=//' | tr -dc 0-9)
[ -n "$FP" ]; check $? "the start menu launched Firefox (pid ${FP:-none})"
[ "$(count 'elevate: ready')" = "$ELEV0" ]; check $? "no consent window for Firefox (elevate: ready stays at $ELEV0)"
grep -aq 'elevate: start .*xfx' "$W/ser"; r=$?; [ "$r" != 0 ]; check $? "no root start through elevate"
[ -n "$FP" ] && grep -aq "execas: user pid=$FP uid=1000" "$W/ser"; check $? "the launcher runs as uid 1000 (execas: user pid=${FP:-none})"
grep -aq 'xfxd: ready' "$W/ser"; check $? "the start service is up (xfxd: ready)"
grep -aq 'xfxd: start uid=1000' "$W/ser"; check $? "the start request reached the service with the session uid (xfxd: start uid=1000)"
! grep -aq 'xfxd: denied' "$W/ser"; check $? "the service refused nobody"
kill $QP 2>/dev/null; wait $QP 2>/dev/null
if [ "$COUNTER" = 1 ]; then
    echo "XFXNOROOT-COUNTERPROOF: $RED/$ALL red"
    [ "$RED" -ge 3 ]
else
    echo "XFXNOROOT: $OK passed, $BAD failed"
    [ "$BAD" -eq 0 ]
fi
