#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbredir/run.sh -- gate "usbtether": USB tethering gadgets end to end in QEMU (NCM, multi-datagram NCM,
# Android composite RNDIS+ADB with several configurations, Android NCM+ADB, hot plug, unplug/replug).
#
#   /root/jarvis/bin/heavy bash tools/usbredir/run.sh [case...]      (default: all cases)
#
# MEASURES (QEMU `-device qemu-xhci -device usb-redir`, the gadget is tools/usbredir/usbdev.py; its Ethernet side is
# a helper QEMU running slirp (DHCP 192.168.42.x, DNS, NAT), frames travel as UDP datagrams):
#   * the kernel enumerates the gadget, picks the right configuration/interface and binds ncm/rndis
#   * DHCP lease over the USB function, ping of the gateway, DNS lookup through the gadget
#   * hot plug AFTER boot (usbhold window), unplug and replug in the same window
# NEGATIVE CONTROLS: no gadget -> no driver line, no lease; unpatched wiring would show up as missing driver lines.
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CASES="${*:-ncm ncm-multi android-rndis android-ncm hotplug replug none ch336 ch336-late ch336-nokick ch336-ecmfirst ch336-proc ch336-intr ch336-intr-only ch336-nochintr ch336-alt1 ch336-alt1-nochalt ch336-alt1-nosetif ch336-hub ch336-2hc ch336-lasthc usbsum usbsum-none hubhot hubhot-norescan}"
source "$HERE/tools/usbredir/common.sh"
for c in $CASES; do
    case "$c" in
    ncm)
        run ncm ncm boot s.sh
        chk ncm "bound to driver ncm" 'driver=ncm'
        net_ok ncm
        chk ncm "DNS through the gadget" '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\s*$'
        ;;
    ncm-multi)
        run ncmm ncm-multi boot s.sh
        chk ncmm "bound to driver ncm (3 datagrams per NTB offered)" 'driver=ncm'
        net_ok ncmm
        grep -a 'rx=' "$T/ncmm.gadget" | tail -1
        ;;
    android-rndis)
        run andr android-rndis boot s.sh
        grep -aq 'set_configuration 2' "$T/andr.gadget" && ok "andr: gadget saw set_configuration 2" || bad "andr: gadget never got configuration 2 ($(grep -a configuration "$T/andr.gadget" | head -2 | tr '\n' ' '))"
        chk andr "bound to driver rndis" 'driver=rndis'
        net_ok andr
        ;;
    android-ncm)
        run andn android-ncm boot s.sh
        chk andn "bound to driver ncm behind the ADB interface" 'driver=ncm'
        net_ok andn
        ;;
    hotplug)
        run hot ncm hot s_hot.sh
        chk hot "hold window ran" 'k17: hold'
        chk hot "bound to driver ncm after boot" 'driver=ncm'
        net_ok hot
        ;;
    replug)
        run re ncm replug s_re.sh
        chk re "bound to driver ncm" 'driver=ncm'
        chk re "unplug noticed" 'usbnet: detached'
        panics re
        ;;
    ch336)
        GARGS="--phy-boot down" run ch ch336 boot s.sh
        chk ch "bound to driver ch336" 'driver=ch336'
        grep -aq 'phy kick #1 via 0x1F' "$T/ch.gadget" && ok "ch: gadget saw the PHY kick" || bad "ch: gadget never saw a PHY kick"
        chk ch "link up with BMCR restored and one kick" 'usb: ch336 link=[a-z]* bmsr=782d .* bmcr=1000 kicks=01'
        net_ok ch
        ;;
    ch336-late)
        GARGS="--phy-boot an" run chl ch336 boot s_late.sh
        grep -aq 'phy kick #1' "$T/chl.gadget" && ok "chl: kick after the link wait" || bad "chl: no kick after the link wait"
        chk chl "link came up after the kick" 'usb: ch336 link=up'
        net_ok chl
        ;;
    ch336-nokick)
        GARGS="--phy-boot down" XWORDS="nophykick" run chn ch336 boot s.sh
        chk chn "bound to driver ch336" 'driver=ch336'
        grep -aq 'phy kick' "$T/chn.gadget" && bad "chn: kick sent despite nophykick" || ok "chn: no kick sent"
        nochk chn "no link without the kick" 'usb: ch336 link=up'
        chk chn "link down with kicks=00" 'usb: ch336 link=down .* kicks=00'
        nochk chn "no lease without the kick" 'dhcp: ack ip='
        panics chn
        ;;
    ch336-ecmfirst)
        GARGS="--phy-boot down" run che ch336-ecmfirst boot s.sh
        chk che "vendor configuration wins over ECM" 'driver=ch336'
        nochk che "ECM not bound" 'driver=ecm'
        net_ok che
        ;;
    ch336-proc)
        GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run chp ch336 boot s_proc.sh
        chk chp "usb line with id" 'usb: ch336 id=1a86:5394'
        chk chp "configuration seen" 'usb: ncfg=2 cfg=1 setcfg=1 rc=0'
        chk chp "interface vendor class" 'usb: iface=ff/ff/ff'
        chk chp "bring-up finished" 'usb: step=4 ok'
        chk chp "debug counters line" 'usb: dbg starts=1 passes=1 unit=0 descs=1 rec=live'
        chk chp "raw device descriptor" 'usb: dev18=1201.*861a9453'
        chk chp "config header" 'usb: cfghdr c0 total='
        chk chp "raw config descriptor" 'usb: cfg0=0902'
        chk chp "parsed interface and endpoint list" 'usb: c0 i0 a0 ff/ff/ff n'
        chk chp "alt scan not needed, SET_INTERFACE sent and accepted" 'usb: alt=0 scan=0 setif=1'
        grep -aq 'set_alt_setting if=0 alt=0' "$T/chp.gadget" && ok "chp: gadget saw SET_INTERFACE alt 0" || bad "chp: gadget never saw SET_INTERFACE alt 0"
        chk chp "phy line with kick count" 'phy: bmcr=1000 bmsr=782d id=0e400141'
        chk chp "link up line" 'link: state=up'
        chk chp "usbnet counters" 'usbnet: ready mode=3 link=up'
        chk chp "dhcp line" 'dhcp: state='
        ;;
    ch336-hub)
        BEHIND_HUB=1 GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run chh ch336 boot s_proc.sh
        chk chh "bound to driver ch336 behind a hub" 'driver=ch336'
        chk chh "usb line with id behind a hub" 'usb: ch336 id=1a86:5394'
        chk chh "bring-up finished behind a hub" 'usb: step=4 ok'
        chk chh "bulk endpoints found behind a hub" 'usb: ep in=[1-9]'
        chk chh "usbnet ready behind a hub" 'usbnet: ready mode=3'
        ;;
    ch336-2hc)
        XHCI2="-device qemu-xhci,id=x1" GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run ch2 ch336 boot s_proc.sh
        chk ch2 "bound to driver ch336 with two controllers" 'driver=ch336'
        chk ch2 "usb line with id with two controllers" 'usb: ch336 id=1a86:5394'
        chk ch2 "bulk endpoints found with two controllers" 'usb: ep in=[1-9]'
        ;;
    ch336-lasthc)
        XHCI2="-device qemu-xhci,id=x1" REDIR_BUS=x1.0 GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run chl2 ch336 boot s_proc.sh
        chk chl2 "dongle on the last controller survives the controller choice" 'usb: dbg starts=[1-9] passes=2'
        chk chl2 "dongle record still live" 'rec=live'
        chk chl2 "bulk endpoints found" 'usb: ep in=[1-9]'
        chk chl2 "usbnet ready" 'usbnet: ready mode=3'
        ;;
    ch336-intr)
        GARGS="--phy-boot down --intr link" BASEW="nokbd nosched vfs" run chi ch336 boot s_proc.sh
        grep -aq 'interrupt packet 40' "$T/chi.gadget" && ok "chi: gadget sent an interrupt packet with the link bit" || bad "chi: no interrupt packet with the link bit"
        chk chi "interrupt endpoint open and polled" 'intr: open=1 ep=3 n=[1-9]'
        chk chi "interrupt byte 0x40 means link up" 'last=0x40 link=up'
        chk chi "link up line" 'link: state=up'
        net_ok chi
        ;;
    ch336-intr-only)
        GARGS="--phy-boot down --phy-deaf --intr up" QWAIT=45 BASEW="nokbd nosched noproc nofs noring3" run chy ch336 boot s_intr.sh
        chk chy "bring-up saw no PHY link" 'usb: ch336 link=down bmsr=7809'
        chk chy "link went up on the interrupt byte while the PHY stayed down" 'usb: ch336 link=up bmsr=7809'
        panics chy
        ;;
    ch336-nochintr)
        GARGS="--phy-boot down --phy-deaf --intr up" XWORDS="nochintr" QWAIT=45 BASEW="nokbd nosched noproc nofs noring3" run chx ch336 boot s_intr.sh
        chk chx "bring-up saw no PHY link" 'usb: ch336 link=down bmsr=7809'
        nochk chx "link not taken from the interrupt" 'usb: ch336 link=up'
        grep -aq 'interrupt packet' "$T/chx.gadget" && bad "chx: interrupt endpoint was opened despite nochintr" || ok "chx: interrupt endpoint not opened"
        panics chx
        ;;
    ch336-alt1)
        GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run ca1 ch336-alt1 boot s_proc.sh
        chk ca1 "bound to driver ch336" 'driver=ch336'
        chk ca1 "bulk endpoints taken from alt 1" 'usb: ep in=[1-9][0-9]* out=[1-9][0-9]*'
        chk ca1 "alt scan picked alt 1, SET_INTERFACE accepted" 'usb: alt=1 scan=1 setif=1'
        grep -aq 'set_alt_setting if=0 alt=1' "$T/ca1.gadget" && ok "ca1: gadget saw SET_INTERFACE alt 1" || bad "ca1: gadget never saw SET_INTERFACE alt 1"
        grep -aq 'bulk STALL' "$T/ca1.gadget" && bad "ca1: bulk transfer stalled" || ok "ca1: no bulk stall"
        net_ok ca1
        ;;
    ch336-alt1-nochalt)
        GARGS="--phy-boot down" XWORDS="nochalt" QWAIT=70 BASEW="nokbd nosched vfs" run ca2 ch336-alt1 boot s_procd.sh
        chk ca2 "bound to driver ch336" 'driver=ch336'
        chk ca2 "no bulk endpoints without the alt scan" 'usb: ep in=0 out=0'
        chk ca2 "no scan reported" 'usb: alt=0 scan=0'
        nochk ca2 "no lease without the alt scan" 'dhcp: ack ip='
        panics ca2
        ;;
    ch336-alt1-nosetif)
        GARGS="--phy-boot down" XWORDS="nosetif" QWAIT=70 BASEW="nokbd nosched vfs" run ca3 ch336-alt1 boot s_procd.sh
        grep -aq 'set_alt_setting if=0 alt=1' "$T/ca3.gadget" && bad "ca3: SET_INTERFACE sent despite nosetif" || ok "ca3: no SET_INTERFACE sent"
        grep -aq 'stats\|tx=' "$T/ca3.gadget" && grep -aq 'stats tx=0' "$T/ca3.gadget" && ok "ca3: no frame reached the gadget" || bad "ca3: frames reached the gadget without SET_INTERFACE"
        chk ca3 "alt scan reported with SET_INTERFACE refused" 'usb: alt=1 scan=1 setif=0'
        nochk ca3 "no lease without SET_INTERFACE" 'dhcp: ack ip='
        panics ca3
        ;;
    usbsum)
        BASEW="nokbd nosched vfs" run usum ch336 boot s_sum.sh
        chk usum "summary header" 'usbsum v1 hc=1 sel=0 passes=1'
        chk usum "controller line with ports and init state" 'h0 0x00:0x0[0-9a-f]\.0x0 .* init=ok ports='
        chk usum "connected root port line with step mask" 'h0p[0-9][0-9] U[23] pre=.* fin=.*[13579bdf] m=0x[7f][0-9a-f]'
        chk usum "device line with the dongle id" 'dev p=[0-9]* hp=0 spd=[0-9]* 0x1a86:0x5394'
        chk usum "log line counts" 'log hcrst=1 halt=[0-9]* ppclr=[0-9]* late hcrst=0 halt=0 ppclr=0'
        chk usum "script reached the end" '==END=='
        panics usum
        ;;
    usbsum-none)
        BASEW="nokbd nosched vfs" run usnone ncm none s_sum.sh
        chk usnone "summary header" 'usbsum v1 hc=1'
        nochk usnone "no dongle device line" '1a86:5394'
        nochk usnone "no connected port without a gadget" 'h0p[0-9][0-9] .*m=[1-9a-f]'
        chk usnone "script reached the end" '==END=='
        ;;
    hubhot)
        BEHIND_HUB=1 GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run hh ch336 hot s_hubhot.sh
        chk hh "hold window ran" 'k17: hold'
        chk hh "dongle found behind the hub after boot" 'usb: ch336 id=1a86:5394'
        chk hh "dongle bound after boot" 'driver=ch336'
        chk hh "hub rescan found the child" 'dev p=[0-9]* hp=[1-9]'
        chk hh "script reached the end" '==END=='
        panics hh
        ;;
    hubhot-norescan)
        BEHIND_HUB=1 XWORDS="usbnorescan" GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run hn ch336 hot s_hubhot.sh
        chk hn "hold window ran" 'k17: hold'
        nochk hn "no dongle found without the rescan" 'usb: ch336 id=1a86:5394'
        chk hn "script reached the end" '==END=='
        ;;
    none)
        run none ncm none s.sh
        nochk none "no driver line without a gadget" 'driver=ncm'
        nochk none "no lease without a gadget" 'dhcp: ack ip='
        chk none "script reached the end" '==END=='
        ;;
    esac
done
echo "USBTETHER: $pass ok, $fail fail"
if [ "$fail" -gt 0 ]; then
    grep -a "usb\|netdev\|nic:\|dhcp\|ncm\|rndis" "$T"/*.klar | cut -c1-170 | head -40
    [ -n "${USBTETHER_WORK:-}" ] || cp -r "$T" /root/tether-fail 2>/dev/null
    exit 1
fi
exit 0
