#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "WLANAUTO: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
SNAPS=${WLANAUTO_SNAPS:-8}
SNAP_SEC=${WLANAUTO_SNAP_SEC:-8}

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANAUTO: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANAUTO: $pass ok, $fail fail"; exit 1; }
{
    echo 'echo ==START=='
    i=0
    while [ "$i" -lt "$SNAPS" ]; do
        echo "sleep $SNAP_SEC"
        echo "echo ==SNAP $i =="
        echo 'cat /proc/wlan'
        i=$((i+1))
    done
    echo 'echo ==END=='
} > "$T/s.sh"

image() { # name [conf-file]
    local n=$1 conf=${2:-}
    local extra=()
    [ -n "$conf" ] && extra=("/etc/wlan.conf=$conf")
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" \
        "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/v7.bin" "${extra[@]}" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() { # name words
    local n=$1 words=$2
    timeout 400 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}

printf 'ssid OrientFake\npsk orient-fake-pw1\n' > "$T/good.conf"
printf 'ssid OrientFake\npsk wrong-password-9\n' > "$T/wrong.conf"
image a || { bad "image a"; exit 1; }
image b "$T/wrong.conf" || { bad "image b"; exit 1; }
image c "$T/good.conf" || { bad "image c"; exit 1; }

echo "-- A: no /etc/wlan.conf: scan lines, no join"
run a "iwlfhtest iwlfhbind"
A="$T/a.klar"
has "$A" 'phase=ready' "driver ready"
has "$A" 'driver=bound' "fake transport bound by wlan_auto"
has "$A" 'net OrientFake ' "scan line: OrientFake"
has "$A" 'net CafeOpen ' "scan line: CafeOpen"
has "$A" 'net Neighbor5 ' "scan line: Neighbor5"
has "$A" 'auto=no-conf' "autostart state no-conf"
hasnot "$A" 'fakeap: m1' "no handshake attempted"
hasnot "$A" 'ip=192.' "no lease"
has "$A" '==END==' "system keeps running"

echo "-- B: wrong password: MIC check fails in the fake AP, retry, never up"
run b "iwlfhtest iwlfhbind"
B="$T/b.klar"
has "$B" 'fakeap: m2 badmic' "fake AP rejects message 2 (bad MIC)"
hasnot "$B" 'fakeap: m4 ok' "handshake never completes"
hasnot "$B" 'auto=up' "never up"
hasnot "$B" 'ip=192.' "no lease"
grep -aE 'auto=retry rc=-[0-9]+ tries=[1-9]' "$B" >/dev/null && ok "state retry with error code and tries counter" || bad "retry state missing"
has "$B" '==END==' "system keeps running"

echo "-- C: correct password: join, WPA2 4-way, DHCP, lease .50"
run c "iwlfhtest iwlfhbind"
C="$T/c.klar"
has "$C" 'fakeap: m2 ok' "fake AP verified message 2 MIC"
has "$C" 'fakeap: m4 ok' "4-way handshake completed (message 4 verified)"
has "$C" 'auto=up rc=0' "autostart state up"
has "$C" 'ip=192.168.77.50 mask=255.255.255.0 gw=192.168.77.1' "lease 192.168.77.50 / 255.255.255.0 / gw .1"
hasnot "$C" 'fakeap: m2 badmic' "no MIC failure"
has "$C" '==END==' "system keeps running"
has "$C" 'fakefw: scan ok v7 slots=52 nchan=35' "W-WLAN17: scan request is v7 with 52 channel slots (from the blob TLVs), 35 channels used"
hasnot "$C" 'fakefw: scan bad' "W-WLAN17: the fake firmware format check never fails"
has "$C" 'fakefw: umac hdr ok wide cmd=' "r2341: SCAN_CFG goes out with the wide header (group 1, length field) like iwlwifi"
hasnot "$C" 'fakefw: umac hdr bad' "r2341: no UMAC command with a short or broken header"

has "$C" 'fakefw: scd ok q4' "W-WLAN19: SCD_QUEUE_CFG v1 for queue 4 accepted by the format check"
has "$C" 'fakefw: addsta q4 ok' "W-WLAN19: ADD_STA carries tfd_queue_msk BIT(4)"
has "$C" 'fakefw: tx ok q4' "W-WLAN19: data frames go through DQA queue 4 (seq, scratch pointer, byte-count table)"
hasnot "$C" 'fakefw: tx bad' "W-WLAN19: no malformed TX descriptor"
hasnot "$C" 'fakefw: addsta q4 missing' "W-WLAN19: queue mask never missing"
has "$C" 'fakefw: phy ok ch=1 band=1 tx=3 rx=5126' "W-WLAN22: PHY_CONTEXT_CMD is the 36-octet v1 layout (band, channel, width, ctrl_pos octets), 2.4 GHz channel 1"
hasnot "$C" 'fakefw: phy bad' "W-WLAN22: the fake firmware phy check never fails"
hasnot "$C" 'diag: fwerr' "W-WLAN4: no firmware error table captured in the normal case"
hasnot "$C" 'diag: umac' "W-WLAN5: no UMAC error table captured in the normal case"

printf 'echo ==START==\nsleep 6\ncat /proc/wlan\necho ==END==\n' > "$T/s.sh"
for ctl in "d iwloldscan 'bad length' a" "e iwloldslot 'bad length' a" "f iwloldssid 'ssid bitmap missing' c"; do
    eval set -- $ctl
    echo "-- $1: counter-proof $2 (old driver behaviour must be refused by the fake firmware)"
    image "$1" "$( [ "$4" = c ] && echo "$T/good.conf" )" || { bad "image $1"; continue; }
    run "$1" "iwlfhtest iwlfhbind $2"
    has "$T/$1.klar" "fakefw: scan bad $3" "$2: fake firmware names the format error"
    if [ "$2" = iwloldssid ]; then
        has "$T/$1.klar" 'fakefw: scan ok' "$2: the broadcast scan is still accepted"
        hasnot "$T/$1.klar" 'fakeap: m4 ok' "$2: no handshake after the refused directed scan"
    else
        hasnot "$T/$1.klar" 'fakefw: scan ok' "$2: no scan accepted"
        hasnot "$T/$1.klar" 'net OrientFake ' "$2: no network found (fake AP stays silent)"
    fi
done

has "$C" 'fakefw: sta 06:11:22:33:44:55' "W-WLAN18: station address comes from NVM section 11 (MAC override)"
echo "-- g: counter-proof iwloldmac (NVM override ignored, WFMP/default address)"
image g || { bad "image g"; }
run g "iwlfhtest iwlfhbind iwloldmac"
has "$T/g.klar" 'fakefw: sta 02:4f:52:49:45:4e' "iwloldmac: the old address is used"
hasnot "$T/g.klar" 'fakefw: sta 06:11:22:33:44:55' "iwloldmac: override not applied"

echo "-- h: counter-proof iwloldtxq (data frames on the command queue)"
image h "$T/good.conf" || { bad "image h"; }
run h "iwlfhtest iwlfhbind iwloldtxq"
has "$T/h.klar" 'fakefw: tx bad on cmd queue' "iwloldtxq: fake firmware refuses data frames on queue 0"
has "$T/h.klar" 'fakefw: addsta q4 missing' "iwloldtxq: ADD_STA without the queue bit is named"
hasnot "$T/h.klar" 'fakeap: m4 ok' "iwloldtxq: no handshake without data TX"
hasnot "$T/h.klar" 'fakefw: tx ok q4' "iwloldtxq: no accepted DQA frame"

echo "-- ph: counter-proof iwloldphy (40-octet PHY_CONTEXT_CMD with a 32-bit channel, silent firmware as on the HP)"
image ph "$T/good.conf" || { bad "image ph"; }
run ph "iwlfhtest iwlfhbind iwloldphy"
has "$T/ph.klar" 'fakefw: phy bad length' "iwloldphy: fake firmware names the wrong PHY_CONTEXT length"
hasnot "$T/ph.klar" 'fakefw: phy ok' "iwloldphy: no PHY context accepted"
hasnot "$T/ph.klar" 'fakefw: scan ok' "iwloldphy: no scan after the silent PHY_CONTEXT"
hasnot "$T/ph.klar" 'fakeap: m4 ok' "iwloldphy: no handshake"
has "$T/ph.klar" 'diag: umac ptr=0x800300 valid=0x1 id=0x7a blink2=0xb10c0003 ilink1=0x11c00002 data1=0x8 data2=0x' "W-WLAN5: UMAC error table read through HBUS 0x40C/0x41C (PHY_CONTEXT)"
has "$T/ph.klar" 'diag: fwerr ptr=0x800200 valid=0x1 id=0x71 blink2=0xb10c0002 ilink1=0x11c00001 data1=0x8 data2=0x' "W-WLAN4: firmware error table read through HBUS 0x40C/0x41C (PHY_CONTEXT)"

echo "-- oi: counter-proof iwloldinit (RT init without SF_CFG/BT_CONFIG: PHY_CFG rejected, firmware silent as on the HP)"
image oi "$T/good.conf" || { bad "image oi"; }
run oi "iwlfhtest iwlfhbind iwloldinit"
hasnot "$T/oi.klar" 'phase=ready' "iwloldinit: driver never ready"
hasnot "$T/oi.klar" 'fakeap: m4 ok' "iwloldinit: no handshake"
has "$T/oi.klar" 'init nvm' "iwloldinit: boot line present"
has "$C" 'phase=ready' "W-WLAN5: Linux RT order (SF_CFG, TX_ANT, PHY_DB, PHY_CFG, BT_CONFIG) is accepted by the fake firmware"
has "$T/oi.klar" 'fail_send=-70 cmd=0x6a' "W-WLAN6: boot failure keeps the real send rc (-70) and the command (PHY_CFG), not only -61"
has "$T/oi.klar" 'fail_lmac ptr=0x00800200 valid=0x00000001 id=0x00000071' "W-WLAN6: LMAC table captured on a RT-stage failure"
has "$T/oi.klar" 'fail_umac ptr=0x00800300 valid=0x00000001 id=0x0000007a' "W-WLAN6: UMAC table captured on a RT-stage failure"
has "$T/oi.klar" 'fail_regs=' "W-WLAN6: CSR snapshot taken on a RT-stage failure"

echo "-- rv1/rv3: RT order variants via iwlrt=N (1 = no SF_CFG, 3 = PHY_CFG before PHY_DB)"
image rv1 "$T/good.conf" || { bad "image rv1"; }
run rv1 "iwlfhtest iwlfhbind iwlrt=1"
hasnot "$T/rv1.klar" 'phase=ready' "iwlrt=1: fake firmware stays silent without SF_CFG"
has "$T/rv1.klar" 'fail_send=-70 cmd=0x6a' "iwlrt=1: PHY_CFG is the failing command"
has "$T/rv1.klar" 'fail_lmac ptr=0x00800200' "iwlrt=1: LMAC table printed"
image rv3 "$T/good.conf" || { bad "image rv3"; }
run rv3 "iwlfhtest iwlfhbind iwlrt=3"
has "$T/rv3.klar" 'phase=ready' "iwlrt=3: PHY_CFG before PHY_DB is a working variant"
has "$T/rv3.klar" 'fakeap: m4 ok' "iwlrt=3: join completes"

pmkfield() { grep -aoE "wlan: pmk steps [0-9]+ max_us [0-9]+" "$1" | head -1 | awk -v f="$2" '{print (f=="steps") ? $4 : $6}'; }
cs=$(pmkfield "$C" steps); cm=$(pmkfield "$C" max)
[ -n "$cs" ] && [ "$cs" -ge 16 ] && ok "W-WLAN20: PMK computed in $cs steps with a yield after each" || bad "W-WLAN20: PMK step count '$cs'"
[ -n "$cm" ] && [ "$cm" -lt 20000 ] && ok "W-WLAN20: longest PMK block ${cm} us < 20000 us" || bad "W-WLAN20: longest PMK block '$cm' us"
echo "-- i: counter-proof iwloldpbkdf (PBKDF2 in one block)"
image i "$T/good.conf" || { bad "image i"; }
run i "iwlfhtest iwlfhbind iwloldpbkdf"
is=$(pmkfield "$T/i.klar" steps); im=$(pmkfield "$T/i.klar" max)
[ "$is" = 1 ] && ok "iwloldpbkdf: one single step" || bad "iwloldpbkdf: steps '$is'"
[ -n "$im" ] && [ -n "$cm" ] && [ "$im" -gt $((cm * 4)) ] && [ "$im" -ge 20000 ] && ok "iwloldpbkdf: one block of ${im} us vs ${cm} us staged" || bad "iwloldpbkdf: block '$im' us not clearly longer than staged '$cm' us"
has "$T/i.klar" 'fakeap: m4 ok' "iwloldpbkdf: the join still completes (same PMK)"

printf 'echo ==START==\nsleep 30\necho ==SNAP 0==\ncat /proc/wlan\nsleep 30\necho ==SNAP 1==\ncat /proc/wlan\nsleep 30\necho ==SNAP 2==\ncat /proc/wlan\necho ==END==\n' > "$T/s.sh"
echo "-- j: AP vanishes after the lease (iwlfhdrop): probe, link lost, reconnect"
image j "$T/good.conf" || { bad "image j"; }
run j "iwlfhtest iwlfhbind iwlfhdrop"
J="$T/j.klar"
has "$J" 'fakeap: drop' "W-WLAN20: fake AP goes deaf after the lease"
has "$J" 'wlan: link probe 0' "W-WLAN20: quiet link triggers the ARP probe"
has "$J" 'wlan: link lost 1' "W-WLAN20: unanswered probe declares the link lost"
[ "$(grep -ac 'fakeap: m4 ok' "$J")" -ge 2 ] && ok "W-WLAN20: second 4-way handshake after the loss" || bad "W-WLAN20: no second handshake"
grep -aqE 'link losses=[1-9][0-9]* reconnects=[1-9][0-9]*' "$J" && ok "W-WLAN20: /proc/wlan reports losses and reconnects" || bad "W-WLAN20: /proc/wlan counters missing"
awk '/==SNAP 2==/{f=1} f' "$J" | grep -aq 'auto=up rc=0' && ok "W-WLAN20: up again at the end" || bad "W-WLAN20: not up again"
hasnot "$J" 'fakefw: tx bad' "W-WLAN20: no malformed TX descriptor on reconnect"
hasnot "$J" 'wlan: link lost 2' "W-WLAN21: no false alarm after the reconnect"
awk '/==SNAP 2==/{f=1} f' "$J" | grep -aq 'link losses=1 reconnects=1' && ok "W-WLAN21: exactly one loss, one reconnect at the end" || bad "W-WLAN21: loss counters wrong"
[ "$(grep -ac 'fakeap: arp' "$J")" -ge 3 ] && ok "W-WLAN21: several probes after the reconnect are answered" || bad "W-WLAN21: too few answered probes"
echo "-- l: counter-proof iwloldrx (device read only while the stack has a free slot): false alarm after the reconnect"
image lr "$T/good.conf" || { bad "image lr"; }
run lr "iwlfhtest iwlfhbind iwlfhdrop iwloldrx"
R="$T/lr.klar"
has "$R" 'wlan: link lost 1' "iwloldrx: the first loss is real"
has "$R" 'wlan: link lost 2' "iwloldrx: false alarm after the reconnect"
grep -aqE 'link losses=([2-9]|[1-9][0-9]+) ' "$R" && ok "iwloldrx: counters show the false alarm" || bad "iwloldrx: counters missing"
echo "-- k: counter-proof iwloldloss (no beacon-loss detection)"
image lk "$T/good.conf" || { bad "image lk"; }
run lk "iwlfhtest iwlfhbind iwlfhdrop iwloldloss"
K="$T/lk.klar"
has "$K" 'fakeap: drop' "iwloldloss: the AP still vanishes"
hasnot "$K" 'wlan: link lost' "iwloldloss: the loss is never noticed"
hasnot "$K" 'wlan: link probe' "iwloldloss: no probe"
[ "$(grep -ac 'fakeap: m4 ok' "$K")" -eq 1 ] && ok "iwloldloss: no reconnect" || bad "iwloldloss: unexpected handshake count"
has "$K" 'link losses=0 reconnects=0' "iwloldloss: counters stay zero"

echo "-- hd: counter-proof iwloldhdr (UMAC scan commands with the short header, as before r2341)"
printf 'echo ==START==\nsleep 14\ncat /proc/wlan\necho ==END==\n' > "$T/s.sh"
image hd || { bad "image hd"; }
run hd "iwlfhtest iwlfhbind iwloldhdr"
HD="$T/hd.klar"
has "$HD" 'fakefw: umac hdr bad short cmd=' "iwloldhdr: the fake firmware drops the short-header SCAN_CFG silently"
has "$HD" 'diag: step=scan_cfg err=-70' "iwloldhdr: same signature as the HP (scan_cfg err=-70)"
hasnot "$HD" 'net OrientFake ' "iwloldhdr: no network found"
echo "-- sw: TX command switches wltxoff + wlbcbytes (bytes in the byte-count table, MH pad only, pm timeout) join like the default"
printf 'echo ==START==\nsleep 14\ncat /proc/wlan\ncat /proc/wlan_trace\necho ==END==\n' > "$T/s.sh"
image sw "$T/good.conf" || { bad "image sw"; }
run sw "iwlfhtest iwlfhbind wltrace wltxoff wlbcbytes"
SW="$T/sw.klar"
has "$SW" 'fakeap: m4 ok' "switches on: 4-way handshake completes"
has "$SW" 'fakefw: tx ok q4' "switches on: the fake firmware accepts the data-queue TX command (byte-count entry in either form)"
hasnot "$SW" 'fakefw: tx bad' "switches on: no TX format violation"
has "$SW" 'diag: dq sent=' "switches on: the data-queue counters are in /proc/wlan"
has "$SW" ' hdata host ' "switches on: the data-queue TX command is in the register trace"
has "$SW" 'ip=192.168.77.50 mask=255.255.255.0 gw=192.168.77.1' "switches on: lease 192.168.77.50"
bash tools/sync/build.sh "$T/bin" 0 wlanctl > "$T/b2.txt" 2>&1 && ok "wlanctl builds" || { bad "wlanctl build"; tail "$T/b2.txt"; }
echo "-- rt: runtime knobs while the driver is bound (wlanctl reload) + /etc/wlan.knobs at boot"
section() { awk -v a="==$2==" -v b="==$3==" '$0 ~ a {f=1; next} $0 ~ b {f=0} f' "$1"; }
rt_image() { # name script [knobs-file]
    printf '%s' "$2" > "$T/$1.sh"
    local extra=()
    [ -n "${3:-}" ] && extra=("/etc/wlan.knobs=$3")
    bash tools/mkfsfi/mkfs.sh build "$T/$1.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/wlanctl="$T/bin/wlanctl.elf" \
        "/t/s.sh=$T/$1.sh" "$FWPATH=$T/blobs/v7.bin" "/etc/wlan.conf=$T/good.conf" "${extra[@]}" > "$T/$1.mkfs" 2>&1
}
RT_SCRIPT=$'echo ==START==\nsleep 14\necho ==BEFORE==\ncat /proc/wlan\nwlanctl reload list\nwlanctl reload wltxoff on\nwlanctl reload wlbcbytes on\nwlanctl reload iwlnoipoll on\necho ==AFTER==\nwlanctl reload list\ncat /proc/wlan\nwlanctl radio off\nsleep 4\nwlanctl radio on\nsleep 14\necho ==REJOIN==\ncat /proc/wlan\nwlanctl reload wltxoff off\nwlanctl reload list\ncat /proc/wlan\necho ==END==\n'
rt_image rt "$RT_SCRIPT" || bad "image rt"
run rt "iwlfhtest iwlfhbind"
RT="$T/rt.klar"
section "$RT" BEFORE AFTER | grep -aq '^wltxoff=off' && ok "runtime: wltxoff starts off" || bad "runtime: wltxoff not off at start"
section "$RT" BEFORE AFTER | grep -aqE 'quirks=0x0[[:space:]]*$' && ok "runtime: live quirk word is 0 before" || bad "runtime: quirk word not 0 before"
section "$RT" AFTER REJOIN | grep -aq '^wltxoff=on' && ok "runtime: wltxoff on while the driver is bound" || bad "runtime: wltxoff refused while bound"
section "$RT" AFTER REJOIN | grep -aq '^wlbcbytes=on' && ok "runtime: wlbcbytes on while the driver is bound" || bad "runtime: wlbcbytes refused while bound"
section "$RT" AFTER REJOIN | grep -aq 'quirks=0x300' && ok "runtime: live quirk word 0x300 (TX_OFF + BC_BYTES) after the knobs" || bad "runtime: quirk word not 0x300"
section "$RT" AFTER REJOIN | grep -aq '^iwlnoipoll=on' && bad "runtime: a boot-only knob changed while bound" || ok "runtime: boot-only knob still refused while bound"
section "$RT" REJOIN END | grep -aq 'auto=up rc=0' && ok "runtime: rejoin with the knobs on works" || bad "runtime: no link after the knobs"
section "$RT" REJOIN END | grep -aq '^wltxoff=off' && ok "runtime: wltxoff off again" || bad "runtime: wltxoff not off again"
section "$RT" REJOIN END | grep -aq 'quirks=0x200' && ok "runtime: live quirk word back to 0x200 (only BC_BYTES)" || bad "runtime: quirk word not 0x200"
printf 'wltxoff on\n# comment\nwlbcbytes\nbogusknob on\niwlnoipoll off\n' > "$T/knobs.txt"
KF_SCRIPT=$'echo ==START==\nsleep 14\nwlanctl reload list\ncat /proc/wlan\necho ==SET==\nwlanctl knobs set wltrace,wlswgrp wllq\ncat /etc/wlan.knobs\necho ==BAD==\nwlanctl knobs set wltrace,nosuchknob\ncat /etc/wlan.knobs\necho ==CLR==\nwlanctl knobs clear\ncat /etc/wlan.knobs\necho ==END==\n'
rt_image kf "$KF_SCRIPT" "$T/knobs.txt" || bad "image kf"
run kf "iwlfhtest iwlfhbind iwlnoipoll"
KF="$T/kf.klar"
grep -aq '^wltxoff=on' "$KF" && ok "knob file: wltxoff on from /etc/wlan.knobs" || bad "knob file: wltxoff not on"
grep -aq '^wlbcbytes=on' "$KF" && ok "knob file: a bare name means on" || bad "knob file: wlbcbytes not on"
grep -aq '^iwlnoipoll=off' "$KF" && ok "knob file: explicit off overrides the cmdline word" || bad "knob file: iwlnoipoll not off"
grep -aq 'quirks=0x300' "$KF" && ok "knob file: live quirk word 0x300 at boot" || bad "knob file: quirk word not 0x300"
grep -aq 'auto=up rc=0' "$KF" && ok "knob file: join works with the knobs" || bad "knob file: no link"
section "$KF" SET BAD | grep -aq '^wltrace$' && section "$KF" SET BAD | grep -aq '^wlswgrp$' && section "$KF" SET BAD | grep -aq '^wllq$' && ok "knobs set: comma list and extra word written to /etc/wlan.knobs" || bad "knobs set: file content wrong"
section "$KF" SET BAD | grep -aq '^wltxoff' && bad "knobs set: old file content not replaced" || ok "knobs set: replaces the old content"
section "$KF" BAD CLR | grep -aq '^wltrace$' && ok "knobs set: unknown name rejected, file untouched" || bad "knobs set: unknown name changed the file"
section "$KF" CLR END | grep -aq '^wl' && bad "knobs clear: file not empty" || ok "knobs clear: file empty"
echo "-- ap: airplane mode (wlanctl radio off/on): link drops, no rejoin while off, back up when on; control without the switch"
air_image() { # name script
    printf '%s' "$2" > "$T/$1.sh"
    bash tools/mkfsfi/mkfs.sh build "$T/$1.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/wlanctl="$T/bin/wlanctl.elf" \
        "/t/s.sh=$T/$1.sh" "$FWPATH=$T/blobs/v7.bin" "/etc/wlan.conf=$T/good.conf" > "$T/$1.mkfs" 2>&1
}
AIR_SWITCH=$'echo ==START==\nsleep 14\necho ==UP==\ncat /proc/wlan\nwlanctl radio off\nsleep 6\necho ==OFF==\ncat /proc/wlan\nwlanctl radio\nsleep 6\necho ==OFF2==\ncat /proc/wlan\nwlanctl radio on\nsleep 14\necho ==ON==\ncat /proc/wlan\nwlanctl radio\necho ==END==\n'
AIR_CONTROL=$'echo ==START==\nsleep 14\necho ==UP==\ncat /proc/wlan\nsleep 6\necho ==OFF==\ncat /proc/wlan\nsleep 6\necho ==OFF2==\ncat /proc/wlan\nsleep 14\necho ==ON==\ncat /proc/wlan\necho ==END==\n'
section() { awk -v a="==$2==" -v b="==$3==" '$0 ~ a {f=1; next} $0 ~ b {f=0} f' "$1"; }
air_image ap "$AIR_SWITCH" || bad "image ap"
run ap "iwlfhtest iwlfhbind"
AP="$T/ap.klar"
section "$AP" UP OFF | grep -aq 'auto=up rc=0' && ok "airplane: the link is up before the switch" || bad "airplane: no link before the switch"
section "$AP" UP OFF | grep -aq 'radio=off' && bad "airplane: radio=off before the switch" || ok "airplane: radio reported on before the switch"
section "$AP" OFF OFF2 | grep -aq 'radio=off' && ok "airplane: /proc/wlan reports radio=off" || bad "airplane: no radio=off in /proc/wlan"
section "$AP" OFF OFF2 | grep -aq 'auto=up rc=0' && bad "airplane: the link is still up with the radio off" || ok "airplane: the link is down with the radio off"
section "$AP" OFF2 ON | grep -aq 'auto=up rc=0' && bad "airplane: the link came back by itself" || ok "airplane: no rejoin while the radio is off"
has "$AP" 'radio off' "airplane: wlanctl reports radio off"
section "$AP" ON END | grep -aq 'auto=up rc=0' && ok "airplane: the link is up again after radio on" || bad "airplane: no link after radio on"
section "$AP" ON END | grep -aq 'radio=off' && bad "airplane: radio=off after radio on" || ok "airplane: radio=off is gone after radio on"
air_image apc "$AIR_CONTROL" || bad "image apc"
run apc "iwlfhtest iwlfhbind"
APC="$T/apc.klar"
section "$APC" OFF OFF2 | grep -aq 'auto=up rc=0' && ok "airplane control: without the switch the link stays up" || bad "airplane control: link lost without the switch"
hasnot "$APC" 'radio=off' "airplane control: no radio=off without the switch"
echo "-- dq: hardware quirk defaults (wltxoff + wllq + wlhwc + wlswgrp) without any knob; wlnodefq switches them off"
DQ_SCRIPT=$'echo ==START==\nsleep 14\ncat /proc/wlan\necho ==END==\n'
air_image dq "$DQ_SCRIPT" || bad "image dq"
run dq "iwlfhtest iwlfhbind wlforcefq"
DQ="$T/dq.klar"
has "$DQ" 'quirks=0x45100' "defaults: live quirk word 0x45100 (TX_OFF + LQ + HWC + SWGRP) with no knob set"
air_image dqn "$DQ_SCRIPT" || bad "image dqn"
run dqn "iwlfhtest iwlfhbind wlforcefq wlnodefq"
DQN="$T/dqn.klar"
has "$DQN" 'quirks=0x0' "defaults: wlnodefq brings the quirk word back to 0"
has "$DQN" 'auto=up rc=0' "defaults: join works without the quirks"
air_image dqf "$DQ_SCRIPT" || bad "image dqf"
run dqf "iwlfhtest iwlfhbind"
has "$T/dqf.klar" 'quirks=0x0' "defaults: fake transport without wlforcefq keeps the old quirk word"
echo "WLANAUTO: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
