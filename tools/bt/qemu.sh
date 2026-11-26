#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CASES="${*:-scan none badclass poweroff bgpump hotplug unplug le lefail leoff}"
source "$HERE/tools/usbredir/common.sh"
BASEW="nokbd nosched vfs"
printf 'echo ==START==\nsleep 2\ncat /proc/bluetooth\necho scan > /dev/btctl\nsleep 4\ncat /proc/bluetooth\ncat /dev/btctl\necho ==END==\n' > "$T/bt.sh"
printf 'echo ==START==\nsleep 2\necho power off > /dev/btctl\necho scan > /dev/btctl\nsleep 2\ncat /proc/bluetooth\necho ==END==\n' > "$T/bt_off.sh"
printf 'echo ==START==\nsleep 1\necho scan > /dev/btctl\nsleep 5\necho ==END==\n' > "$T/bt_bg.sh"
printf 'echo ==START==\nsleep 10\ncat /proc/bluetooth\necho scan > /dev/btctl\nsleep 4\ncat /proc/bluetooth\necho ==END==\n' > "$T/bt_hot.sh"
printf 'echo ==START==\nsleep 1\ncat /proc/bluetooth\ncat /dev/btctl\necho ==END==\n' > "$T/bt_unp.sh"
printf 'echo ==START==\nsleep 2\necho scan > /dev/btctl\nsleep 4\necho lescan > /dev/btctl\nsleep 3\ncat /proc/bluetooth\necho lestop > /dev/btctl\nsleep 1\ncat /proc/bluetooth\necho ==END==\n' > "$T/bt_le.sh"
printf 'echo ==START==\nsleep 2\necho lescan > /dev/btctl\nsleep 2\ncat /proc/bluetooth\necho ==END==\n' > "$T/bt_lefail.sh"
printf 'echo ==START==\nsleep 2\necho power off > /dev/btctl\necho lescan > /dev/btctl\nsleep 2\ncat /proc/bluetooth\necho ==END==\n' > "$T/bt_leoff.sh"
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 8000 /bin/ /t/ /etc/ /dev/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/bt.sh="$T/bt.sh" /t/bt_off.sh="$T/bt_off.sh" /t/bt_bg.sh="$T/bt_bg.sh" /t/bt_hot.sh="$T/bt_hot.sh" /t/bt_unp.sh="$T/bt_unp.sh" /t/bt_le.sh="$T/bt_le.sh" /t/bt_lefail.sh="$T/bt_lefail.sh" /t/bt_leoff.sh="$T/bt_leoff.sh" > "$T/mkfs2.txt" 2>&1 || { tail "$T/mkfs2.txt"; exit 1; }
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
    bgpump)
        run btg btdongle boot bt_bg.sh
        chk btg "inquiry finished without any proc read" 'bt: inquiry done n=3'
        panics btg
        ;;
    hotplug)
        GARGS="--bt normal" run bth btdongle hot bt_hot.sh
        chk bth "bound after boot" 'driver=btusb'
        chk bth "reset ok" 'bt: hci reset ok'
        chk bth "three devices after hotplug" 'devices 3'
        panics bth
        ;;
    unplug)
        GARGS="--bt normal" REPLUG_WAIT='command 0c45' run btu btdongle replug bt_unp.sh
        chk btu "bound" 'driver=btusb'
        chk btu "detach noticed" 'bt: detached'
        chk btu "state none after unplug" 'state none'
        panics btu
        ;;
    le)
        GARGS="--bt normal" run btl btdongle boot bt_le.sh
        grep -aq 'bt: command 0c01 params=ffffffffff1f0020' "$T/btl.gadget" && ok "btl: event mask command sent in init" || bad "btl: event mask command sent in init"
        grep -aq 'bt: command 200b params=01600030000000' "$T/btl.gadget" && ok "btl: le scan params sent" || bad "btl: le scan params sent"
        grep -aq 'bt: command 200c params=0100' "$T/btl.gadget" && ok "btl: le scan enable sent" || bad "btl: le scan enable sent"
        chk btl "one le scan started" 'lescans 1'
        chk btl "five le reports parsed" 'lereports 5'
        chk btl "classic and le devices merged" 'devices 6'
        chk btl "classic device kept" 'dev DE:AD:BE:EF:00:07 -60 computer Test Laptop'
        chk btl "le keyboard with name, class and updated rssi" 'dev C0:11:22:33:44:55 -42 input BLE Keyboard'
        chk btl "le scan response merged into advertiser" 'dev F1:00:00:00:00:01 -68 other Tag F1'
        chk btl "second report of a pair" 'dev F2:00:00:00:00:02 -80 other Thermo'
        chk btl "random address marked" 'le C0:11:22:33:44:55 random'
        chk btl "public address marked" 'le F1:00:00:00:00:01 public'
        nochk btl "classic device not marked le" 'le DE:AD:BE:EF:00:07'
        chk btl "state scanning-free after stop" 'state ready'
        grep -aq 'lescanning=0 leenables=1,0' "$T/btl.gadget" && ok "btl: model saw enable then disable" || bad "btl: model enable/disable order"
        grep -aq 'bt violations=0' "$T/btl.gadget" && ok "btl: model saw no malformed command" || bad "btl: model violations"
        panics btl
        ;;
    lefail)
        GARGS="--bt lefail" run btf btdongle boot bt_lefail.sh
        chk btf "ready" 'bt: hci reset ok'
        chk btf "no le scan counted after refusal" 'lescans 0'
        chk btf "no reports" 'lereports 0'
        panics btf
        ;;
    leoff)
        GARGS="--bt normal" run bto btdongle boot bt_leoff.sh
        chk bto "ready" 'bt: hci reset ok'
        chk bto "power off in proc" 'power off'
        grep -aq 'command 200c' "$T/bto.gadget" && bad "bto: le scan sent while off" || ok "bto: no le scan command sent while off"
        panics bto
        ;;
    esac
done
printf '\nBTQEMU: %d ok, %d fail\n' "$pass" "$fail"
[ "$fail" = 0 ]
