#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sessuid/run.sh -- ROUND SESSUID3 gate: after sign-in, start-menu programmes run as the session user (uid 1000), not root;
# a system tool (Settings) goes through /bin/elevate: Cancel starts nothing, Allow starts it as root (kernel line `execas: priv`).
# Needs a build dir (osum.mb + root.img) of a UITRACE=1 personal image:
#   UITRACE=1 PARTTAB=mbr FS_BLOCKS=122880 IMAGE_ID=x bash tools/usbimg/build.sh <dir>; bash tools/sessuid/run.sh <dir> [old-kernel.mb]
# COUNTER-PROBE: the second argument boots the same root image with an OLD kernel (no syscall 1005): the two checks marked [X] must then fail
# (programmes stay root, Allow has no `execas: priv` line); the gate prints SESSUID-GEGENPROBE: n/n red as wanted.
set -uo pipefail
cd "$(dirname "$0")/../.."
B=${1:?build dir (osum.mb + root.img, UITRACE=1)}
K="$B/osum.mb"; GEG=0
[ -n "${2:-}" ] && { K=$2; GEG=1; }
[ -f "$K" ] && [ -f "$B/root.img" ] || { echo "FAIL: $K or $B/root.img missing"; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OK=0; BAD=0; XRED=0; XALL=0
ok() { OK=$((OK+1)); echo "  OK    $1"; }
bad() { BAD=$((BAD+1)); echo "  FAIL  $1"; }
# [X] checks: green on the new kernel; with the old kernel (GEG=1) they must be RED
xchk() { # cond-result(0=true) text; the "[X]" in the text marks the two kernel-dependent checks
    XALL=$((XALL+1))
    if [ "$GEG" = 1 ]; then
        if [ "$1" != 0 ]; then XRED=$((XRED+1)); echo "  RED   $2 (as wanted with the old kernel)"; else echo "  GREEN $2 (unexpected with the old kernel)"; fi
    else
        if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi
    fi
}
cp "$B/root.img" "$W/d.img"
KVM=(-accel tcg); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
mon() { printf '%s\n' "$1" | timeout 5 socat - "unix-connect:$W/mon" >/dev/null 2>&1; }
keys() { local k; for k in "$@"; do mon "sendkey $k"; sleep 0.4; done; }
timeout 330 qemu-system-x86_64 "${KVM[@]}" -m 512 -kernel "$K" \
    -append "gfx fbres=1024x768 wm wig desk wmshell wmdauer herz anmeldung nosched noproc nofs lang=de uiscale=1" \
    -serial "file:$W/ser" -display none -no-reboot -device VGA,edid=on,xres=1024,yres=768,vgamem_mb=32 \
    -monitor "unix:$W/mon,server,nowait" -drive "file=$W/d.img,format=raw,if=ide,index=0" >/dev/null 2>&1 &
QP=$!
waitfor() { local i; for i in $(seq 1 "$2"); do grep -qa -- "$1" "$W/ser" 2>/dev/null && return 0; sleep 1; done; return 1; }
waitfor 'glogin: bereit' 120; sleep 6
keys s t a r t k e n n w o r t ret
waitfor 'glogin: desktop pid=' 90; sleep 12
# 1. a plain programme from the start menu
mon "sendkey meta_l"; sleep 3
keys e x p l o r e r ret
waitfor 'launcher: start /apps/explorer.osp/start pid=' 40; sleep 5
EP=$(grep -a 'launcher: start /apps/explorer.osp/start pid=' "$W/ser" | tail -1 | sed 's/.*pid=//' | tr -dc 0-9)
[ -n "$EP" ] && ok "the start menu started Explorer (pid $EP)" || bad "Explorer was not started"
grep -aq "execas: user pid=$EP uid=1000" "$W/ser"; xchk $? "[X] Explorer runs as uid 1000 (kernel: execas: user pid=$EP uid=1000)"
# 2. Settings: the consent window comes first, nothing is root yet
mon "sendkey meta_l"; sleep 3
keys e i n s t e l l u n g e n ret
waitfor 'elevate: ready' 40; sleep 3
grep -aq 'elevate: ready' "$W/ser" && ok "Settings opens the consent window (elevate: ready)" || bad "Settings opens the consent window (elevate: ready)"
grep -aq 'elevate: start ' "$W/ser" && bad "a root programme started before consent" || ok "nothing started as root before consent"
# 3. Cancel (Tab Tab Return) -> nothing starts
keys tab tab ret; sleep 4
grep -aq 'elevate: denied' "$W/ser" && ok "Cancel is reported (elevate: denied)" || bad "Cancel is reported (elevate: denied)"
grep -aq 'elevate: start ' "$W/ser" && bad "Cancel still started a root programme" || ok "Cancel started nothing as root"
# 4. Allow (Tab Return) -> Settings starts as root
mon "sendkey meta_l"; sleep 3
keys e i n s t e l l u n g e n ret
waitfor 'elevate: ready' 40; sleep 3; keys tab ret; sleep 8
grep -aq 'elevate: allowed' "$W/ser" && ok "Allow is reported (elevate: allowed)" || bad "Allow is reported (elevate: allowed)"
SP=$(grep -a 'elevate: start /apps/settings.osp/start pid=' "$W/ser" | tail -1 | sed 's/.*pid=//' | tr -dc 0-9)
[ -n "$SP" ] && grep -aq "execas: priv pid=$SP\$" "$W/ser"; xchk $? "[X] Allow starts Settings as root (elevate: start ... pid=$SP and kernel: execas: priv pid=$SP)"
kill $QP 2>/dev/null; wait $QP 2>/dev/null
grep -aq 'glogin: uid=1000' "$W/ser" && ok "the desktop runs as uid 1000" || bad "no 'glogin: uid=1000'"
if [ "$GEG" = 1 ]; then
    echo "SESSUID-GEGENPROBE: $XRED/$XALL red"
    [ "$XRED" -eq "$XALL" ]
else
    echo "SESSUID: $OK passed, $BAD failed"
    [ "$BAD" -eq 0 ]
fi
