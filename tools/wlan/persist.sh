#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/wlan/persist.sh -- W-WLAN16a gate: /etc/wlan.conf survives a restart of the live stick (root = RAM module).
#   bash tools/wlan/persist.sh <build-dir> [old-build-dir]
# <build-dir> holds orientos-usb.img (tools/usbimg/build.sh <dir>). Boot 1 (OVMF q35, xHCI usb-storage like the HP): sign in,
# the session user writes /etc/wlan.conf, wlanpersist mirrors it to the stick's FAT partition (host check with mtools + fsck.fat).
# Boot 2 from the same image: wlanpersist restores it. With old-build-dir (image without wlanpersist) the [X] checks must be RED.
set -uo pipefail
cd "$(dirname "$0")/../.."
B=${1:?build dir}
GEG=0
[ -n "${2:-}" ] && { B=$2; GEG=1; }
[ -f "$B/orientos-usb.img" ] || { echo "FAIL: $B/orientos-usb.img missing"; exit 1; }
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
[ -f "$OVMF_CODE" ] && [ -f "$OVMF_VARS" ] || { echo "FAIL: OVMF firmware missing"; exit 1; }
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
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
OFF=$((2048*512))
cp "$B/orientos-usb.img" "$W/stick.img"
mcopy -i "$W/stick.img@@$OFF" ::limine.conf "$W/limine.conf" || { echo "FAIL: mcopy limine.conf"; exit 1; }
sed 's/^timeout: .*/timeout: 1/' "$W/limine.conf" > "$W/l_norm.conf"
mcopy -i "$W/stick.img@@$OFF" -o "$W/l_norm.conf" ::limine.conf
mon() { printf '%s\n' "$1" | timeout 5 socat - "unix-connect:$W/mon" >/dev/null 2>&1; }
keys() { local k; for k in "$@"; do mon "sendkey $k"; sleep 0.4; done; }
waitfor() { local i; for i in $(seq 1 "$2"); do grep -qa -- "$1" "$W/$3" 2>/dev/null && return 0; sleep 1; done; return 1; }
start_vm() {
    local ser=$1
    cp "$OVMF_VARS" "$W/vars.fd"
    rm -f "$W/mon"
    qemu-system-x86_64 "${KVM[@]}" -machine q35 -m 2048 -smp 2 \
        -drive "file=$W/stick.img,format=raw,if=none,id=stick" -device qemu-xhci -device usb-storage,drive=stick \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF_CODE" -drive "if=pflash,format=raw,unit=1,file=$W/vars.fd" \
        -serial "file:$W/$ser" -display none -no-reboot -monitor "unix:$W/mon,server,nowait" >/dev/null 2>&1 &
    QP=$!
}
stop_vm() { mon "quit"; sleep 2; kill $QP 2>/dev/null; wait $QP 2>/dev/null; }
start_vm ser1
waitfor 'glogin: bereit' 240 ser1; sleep 8
keys s t a r t k e n n w o r t ret
waitfor 'glogin: desktop pid=' 120 ser1; sleep 12
mon "sendkey meta_l"; sleep 3
keys t e r m i n a l ret
waitfor 'launcher: start /apps/terminal.osp/start pid=' 60 ser1; sleep 8
keys e c h o spc s s i d spc g a t e n e t spc shift-less spc shift-7 e t c shift-7 w l a n dot c o n f ret
sleep 2
waitfor 'wlanpersist: saved bytes=' $([ "$GEG" = 1 ] && echo 8 || echo 30) ser1; sleep 4
stop_vm
cp "$W/ser1" "${PERSIST_KEEP:-/dev/null}" 2>/dev/null; grep -aq "wlanpersist: watching" "$W/ser1" && W1=0 || W1=1
xchk $W1 "[X] boot 1: wlanpersist runs on the RAM root (serial: wlanpersist: watching)"
grep -aq 'wlanpersist: saved bytes=13' "$W/ser1" && W2=0 || W2=1
xchk $W2 "[X] boot 1: the save is reported (wlanpersist: saved bytes=13)"
mtype -i "$W/stick.img@@$OFF" ::wlan.cnf > "$W/esp.txt" 2>/dev/null
[ "$(cat "$W/esp.txt")" = "ssid gatenet" ] && H=0 || H=1
xchk $H "[X] the stick's FAT partition holds wlan.cnf = 'ssid gatenet' (read on the host with mtools)"
dd if="$W/stick.img" of="$W/part.img" bs=512 skip=2048 count=196608 status=none
if command -v fsck.fat >/dev/null 2>&1; then
    fsck.fat -n "$W/part.img" > "$W/fsck.txt" 2>&1 && ok "fsck.fat: the FAT partition is consistent after the write" || { bad "fsck.fat complains"; head -5 "$W/fsck.txt"; }
fi
mdir -i "$W/stick.img@@$OFF" :: > "$W/dir.txt" 2>&1
mtype -i "$W/stick.img@@$OFF" ::limine.conf >/dev/null 2>&1 && mtype -i "$W/stick.img@@$OFF" ::osum.mb >/dev/null 2>&1 && ok "kernel and limine.conf are still on the FAT partition" || bad "kernel or limine.conf missing after the write"
start_vm ser2
waitfor 'glogin: bereit' 240 ser2; sleep 8
keys s t a r t k e n n w o r t ret
waitfor 'wlanpersist: ' $([ "$GEG" = 1 ] && echo 60 || echo 240) ser2; sleep 6
stop_vm
cp "$W/ser2" "${PERSIST_KEEP:-/dev/null}2" 2>/dev/null
grep -aq 'wlanpersist: restored bytes=13' "$W/ser2" && R=0 || R=1
xchk $R "[X] boot 2: the saved network comes back (wlanpersist: restored bytes=13)"
grep -aq 'EXCEPTION\|kernel halted\|panic:' "$W/ser2" && bad "boot 2: fault line" || ok "boot 2: no fault line"
if [ "$GEG" = 1 ]; then
    echo "PERSIST-GEGENPROBE: $XRED/$XALL red"
    [ "$XRED" -eq "$XALL" ]
else
    echo "PERSIST: $OK passed, $BAD failed"
    [ "$BAD" -eq 0 ]
fi
