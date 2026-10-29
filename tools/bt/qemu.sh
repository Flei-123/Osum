#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CASES="${*:-scan none badclass poweroff}"
source "$HERE/tools/usbredir/common.sh"
BASEW="nokbd nosched vfs"
printf 'echo ==START==\nsleep 2\ncat /proc/bluetooth\necho scan > /dev/btctl\nsleep 4\ncat /proc/bluetooth\ncat /dev/btctl\necho ==END==\n' > "$T/bt.sh"
printf 'echo ==START==\nsleep 2\necho power off > /dev/btctl\necho scan > /dev/btctl\nsleep 2\ncat /proc/bluetooth\necho ==END==\n' > "$T/bt_off.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/bt.sh="$T/bt.sh" /t/bt_off.sh="$T/bt_off.sh" > "$T/mkfs2.txt" 2>&1 || { tail "$T/mkfs2.txt"; exit 1; }
for c in $CASES; do
    case "$c" in
    scan)
        GARGS="--bt normal" run bt btdongle boot bt.sh
        chk bt "driver bound" 'driver=btusb'
        chk bt "reset ok" 'bt: hci reset ok'
        chk bt "controller address" 'bt: addr 00:1A:7D:DA:71:13'
        chk bt "version line" 'bt: version hci=9 mfr=0x2'
        chk bt "proc ready" 'state ready'
        chk bt "proc controller" 'controller 00:1A:7D:DA:71:13'
        chk bt "three unique devices" 'devices 3'
        chk bt "audio device with rssi" 'dev AA:BB:CC:00:00:01 -40 audio'
        chk bt "phone device" 'dev 11:22:33:44:55:66 ? phone'
        chk bt "extended name" 'dev DE:AD:BE:EF:00:07 -60 computer Test Laptop'
        chk bt "btctl status" 'power on state ready devices 3'
        grep -aq 'bt violations=0' "$T/bt.gadget" && ok "bt: model saw no malformed command" || bad "bt: model violations"
        panics bt
        ;;
    none)
        run btn btdongle none bt.sh
        nochk btn "no controller line" 'bt: hci reset ok'
        chk btn "proc state none" 'state none'
        chk btn "no devices" 'devices 0'
        panics btn
        ;;
    badclass)
        run btb btdongle-badclass boot bt.sh
        nochk btb "wrong protocol not bound" 'driver=btusb'
        nochk btb "no controller line" 'bt: hci reset ok'
        panics btb
        ;;
    poweroff)
        run btp btdongle boot bt_off.sh
        chk btp "ready" 'bt: hci reset ok'
        chk btp "power off in proc" 'power off'
        chk btp "no devices while off" 'devices 0'
        grep -aq 'command 0401' "$T/btp.gadget" && bad "btp: inquiry sent while off" || ok "btp: no inquiry command sent while off"
        panics btp
        ;;
    esac
done
printf '\nBTQEMU: %d ok, %d fail\n' "$pass" "$fail"
[ "$fail" = 0 ]
