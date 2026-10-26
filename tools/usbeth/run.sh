#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
ALL="ax179 ax179-http ax179-ecmfirst ax179-multi ax179-late ax179-down ax179-hot ax179-unplug ax178a rtl8153 rtl-http rtl8153b rtl8152 rtl-multi rtl-late rtl-down rtl-hot rtl-unplug rtl-unknown-chip rtl-unknown-id ax-unknown-id none two hotadd-ecm hotadd-rndis"
CASES="${*:-host $ALL}"
source "$HERE/tools/usbredir/common.sh"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
printf 'echo ==START==\ndhcp\nping 192.168.42.129\nhost example.org\nsleep 2\ncat /proc/usbnet\necho ==END==\n' > "$T/s_nic.sh"
HPORT=$((48000 + ($$ % 500)))
printf 'echo ==START==\ndhcp\nwget -q http://192.168.42.129:%s/x.txt\nsleep 1\ncat /proc/usbnet\necho ==END==\n' "$HPORT" > "$T/s_http.sh"
printf 'echo ==START==\ndhcp\nping 10.0.2.2\nsleep 2\ncat /proc/usbnet\necho ==END==\n' > "$T/s_q.sh"
printf 'echo ==START==\nsleep 5\ncat /proc/usbnet\necho ==END==\n' > "$T/s_down.sh"
printf 'echo ==START==\nsleep 9\ndhcp\nping 192.168.42.129\nsleep 2\ncat /proc/usbnet\necho ==END==\n' > "$T/s_vlate.sh"
bash tools/sync/build.sh "$T/bin" 0 wget > "$T/bw.txt" 2>&1 || { tail "$T/bw.txt"; exit 1; }
mkdir -p "$T/www"
python3 -I -c "import sys;sys.stdout.buffer.write(bytes((i*7+3)&255 for i in range(4000)))" > "$T/www/x.txt"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/cat="$T/bin/cat.elf" /bin/wget="$T/bin/wget.elf" /proc/ \
    /t/s.sh="$T/s.sh" /t/s_hot.sh="$T/s_hot.sh" /t/s_re.sh="$T/s_re.sh" /t/s_nic.sh="$T/s_nic.sh" /t/s_down.sh="$T/s_down.sh" \
    /t/s_vlate.sh="$T/s_vlate.sh" /t/s_http.sh="$T/s_http.sh" /t/s_q.sh="$T/s_q.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }

nic() { BASEW="nokbd nosched vfs" run "$@"; }

hotadd() {
    local n=$1 words=$2 plan=$3
    rm -f "$T/$n".*
    timeout 170 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched vfs noring3 usb usbhold usbpoll nic $words nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s_q.sh;exit" \
        -serial "file:$T/$n.txt" -display none -nic none -no-reboot \
        -monitor "unix:$T/$n.mon,server,nowait" -pidfile "$T/$n.pid" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 -netdev user,id=n0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    python3 -I tools/hotplug/monitor.py "$T/$n.mon" "$T/$n.txt" "$plan" > "$T/$n.monlog" 2>&1
    bash tools/work/waitfor.sh -t 120 -i 2 log "$T/$n.txt" '==END==' >/dev/null 2>&1
    [ -f "$T/$n.pid" ] && kill "$(cat "$T/$n.pid")" 2>/dev/null
    wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}

http_run() {
    (python3 -I -m http.server "$HPORT" --bind 127.0.0.1 -d "$T/www" > "$T/web-$1.log" 2>&1 & echo $! > "$T/web-$1.pid")
    sleep 1
    nic "$1" "$2" boot s_http.sh
    kill "$(cat "$T/web-$1.pid")" 2>/dev/null
}

golden() {
    local n=$1; shift
    python3 -I tools/usbeth/refdrv.py "$@" > "$T/$n.want" 2> "$T/$n.referr"
    sed -n 's/^[0-9.]* \(W .*\)$/\1/p' "$T/$n.gadget" > "$T/$n.got"
    if [ -s "$T/$n.want" ] && cmp -s "$T/$n.want" "$T/$n.got"; then
        ok "$n: kernel driver wrote the same $(wc -l < "$T/$n.want") registers in the same order as the reference"
    else
        bad "$n: register writes differ from the reference (want $(wc -l < "$T/$n.want"), got $(wc -l < "$T/$n.got"))"
        diff "$T/$n.want" "$T/$n.got" | head -8
    fi
}

rxmatch() {
    local n=$1 g u
    g=$(grep -a 'rx total' "$T/$n.gadget" | tail -1 | awk '{print $4}')
    u=$(grep -a 'usbnet: ready mode' "$T/$n.klar" | sed -n 's/.* rx=\([0-9]*\).*/\1/p' | tail -1)
    if [ -n "$g" ] && [ "$g" = "$u" ]; then ok "$n: guest counted $u received frames = $g delivered by the gadget"
    else bad "$n: guest rx count '$u' differs from the gadget '$g'"; fi
}

clean_model() {
    grep -aq 'VIOLATION' "$T/$1.gadget" && bad "$1: model reported a violation: $(grep -a VIOLATION "$T/$1.gadget" | head -1)" || ok "$1: no device-rule violation"
    grep -aq 'bad tx' "$T/$1.gadget" && bad "$1: model rejected a transmit frame: $(grep -a 'bad tx' "$T/$1.gadget" | head -1)" || ok "$1: every transmit frame was well formed"
}

host_checks() {
    local k="$T/hk.fi"
    for m in ax88179 ax88179_drv rtl8153 rtl8153_drv; do
        printf 'import usbnet.%s\nfn main() -> i32 {\n    return 0\n}\n' "$m" > "$k"
        "$FIRNC" --profile=kernel -c "$k" -o "$T/hk.o" 2> "$T/hk.err" && ok "usbnet.$m compiles with --profile=kernel" || { bad "usbnet.$m does not compile for the kernel"; head -5 "$T/hk.err"; }
    done
    if "$FIRNC" tools/usbeth/oracle.fi -o "$T/oracle" > "$T/o.err" 2>&1; then
        "$T/oracle" > "$T/out.txt" 2>&1
        local nok nfail
        nok=$(grep -c '^OK' "$T/out.txt"); nfail=$(grep -c '^FAIL' "$T/out.txt")
        sed -n 's/^FAIL /  FAIL  oracle: /p' "$T/out.txt"
        [ "$nfail" = 0 ] && [ "$nok" -ge 95 ] && ok "oracle: $nok promises hold" || bad "oracle: $nok ok, $nfail fail"
    else
        bad "oracle does not build"; head -8 "$T/o.err"
    fi
    mutate() {
        local name=$1 file=$2 expr=$3
        rm -rf "$T/mut"; mkdir -p "$T/mut"; cp -r lib/. "$T/mut/"
        sed -i "$expr" "$T/mut/usbnet/$file"
        cmp -s "lib/usbnet/$file" "$T/mut/usbnet/$file" && { bad "mutation '$name' changed nothing"; return; }
        if ! FIRNLIB="$T/mut" "$FIRNC" tools/usbeth/oracle.fi -o "$T/oracle-m" > "$T/m.err" 2>&1; then bad "mutation '$name' does not build"; return; fi
        { "$T/oracle-m" > "$T/m.txt" 2>&1; } 2>/dev/null
        mrc=$?
        if grep -q '^FAIL' "$T/m.txt" || [ "$mrc" != 0 ]; then ok "counter-proof: oracle goes red without '$name' ($(grep -c '^FAIL' "$T/m.txt") promises fail, exit $mrc)"
        else bad "counter-proof: oracle stays green without '$name'"; fi
    }
    mutate "ax179 padding flag" ax88179.fi 's/h2 = 0x80008000/h2 = 0/'
    mutate "ax179 trailer bound" ax88179.fi 's/if cnt == 0 || cnt \* 4 + hoff > body { return RX_END }/if cnt == 0 { return RX_END }/'
    mutate "ax179 data bound" ax88179.fi 's/if off + pp > hoff { return RX_BAD }//'
    mutate "ax179 CRC error check" ax88179.fi 's/RXHDR_CRC_ERR | RXHDR_DROP_ERR/RXHDR_DROP_ERR/'
    mutate "ax179 runt check" ax88179.fi 's/ || pl < 16 / /'
    mutate "ax179 8 octet padding" ax88179.fi 's/(pkt_len + 7) \& 0xFFF8/(pkt_len + 3) \& 0xFFFC/'
    mutate "ax179 IP alignment skip" ax88179.fi 's/le.put64(res, 16, off + 2)/le.put64(res, 16, off)/'
    mutate "ax179 bulk-in table" ax88179.fi 's/return 0xFF16032007/return 0xFF16032008/'
    mutate "ax179 speed select" ax88179.fi 's/if (usb_link \& USB_HS) != 0 { return 1 }//'
    mutate "ax179 100M medium" ax88179.fi 's/if cls == LINK_100 { m = m | MEDIUM_PS }//'
    mutate "rtl descriptor flags" rtl8153.fi 's/n | TX_FS | TX_LS/n | TX_FS/'
    mutate "rtl runt stop" rtl8153.fi 's/if pkt < ZLEN { return RX_END }/if pkt < 10 { return RX_END }/'
    mutate "rtl transfer bound" rtl8153.fi 's/if off + RX_DESC + pkt > len { return RX_END }//'
    mutate "rtl 8 octet alignment" rtl8153.fi 's/(v + 7) \& 0xFFFFFFF8/(v + 3) \& 0xFFFFFFFC/'
    mutate "rtl FCS removal" rtl8153.fi 's/le.put64(res, 24, pkt - FCS)/le.put64(res, 24, pkt)/'
    mutate "rtl family table" rtl8153.fi 's/v == 0x6000 || v == 0x6010/v == 0x6000/'
    mutate "rtl early size divisor" rtl8153.fi 's/return room \/ 4/return room \/ 8/'
    mutate "rtl link bit" rtl8153.fi 's/if (phystatus \& PHYST_LINK) == 0 { return LINK_DOWN }//'
    python3 -I tools/usbeth/refdrv.py selftest > "$T/self.txt" 2>&1
    sed -n 's/^  FAIL  /  FAIL  model: /p' "$T/self.txt"
    [ "$(grep -c FAIL "$T/self.txt")" = 0 ] && ok "device models: $(grep -c OK "$T/self.txt") rules hold (a driver that skips a step is refused)" || bad "device model self test failed"
}

for c in $CASES; do
    case "$c" in
    host)
        host_checks
        ;;
    ax179)
        nic ax ax88179 boot s_nic.sh
        chk ax "bound to driver ax88179" 'driver=ax88179'
        nochk ax "ECM not bound" 'driver=ecm'
        chk ax "MAC line from the node id register" 'usb: ax88179 02:11:22:33:44:55'
        chk ax "link up at 1000" 'usbnet: link up 1000'
        chk ax "driver mode 5 ready" 'usbnet: ready mode=5 link=up'
        net_ok ax
        chk ax "DNS through the chip" '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\s*$'
        grep -aq 'medium=013b' "$T/ax.gadget" && ok "ax: medium mode reprogrammed for giga full duplex after the link came up" || bad "ax: no giga medium write"
        golden ax ax179 up ss
        clean_model ax
        rxmatch ax
        ;;
    hotadd-ecm|hotadd-rndis)
        if [ "$c" = hotadd-ecm ]; then drv=ecm; words=""; else drv=rndis; words="rndisonly"; fi
        printf 'aufzeile k17: hold\nmonitor device_add usb-net,id=devn1,netdev=n0,mac=52:54:00:12:34:99\naufzeile driver=%s\nmonitor device_del devn1\naufzeile usbnet: detached\nmonitor device_add usb-net,id=devn2,netdev=n0,mac=52:54:00:12:34:98\naufzeile k17: free\n' "$drv" > "$T/plan-$c.txt"
        hotadd "$c" "$words" "$T/plan-$c.txt"
        H="$T/$c.klar"
        [ "$(grep -ac "class=[0-9a-f:]* driver=$drv" "$H")" = 2 ] && ok "$c: bound to $drv twice (add, remove, add again)" || bad "$c: bound to $drv $(grep -ac "class=[0-9a-f:]* driver=$drv" "$H") times"
        grep -aq 'usbnet: detached' "$H" && ok "$c: device_del noticed" || bad "$c: device_del not noticed"
        grep -aq "$(if [ "$drv" = ecm ]; then echo 'usb: ecm 52:54:00:12:34:98'; else echo 'usb: rndis 52:54:00:12:34:98'; fi)" "$H" && ok "$c: the second device (MAC ...98) was taken after the first was removed" || bad "$c: second device not taken"
        grep -aq 'dhcp: ack ip=10.0.2.15' "$H" && ok "$c: DHCP lease over the re-added device" || bad "$c: no lease"
        grep -aq 'octets from 10.0.2.2: icmp_seq=1' "$H" && ok "$c: ping over the re-added device" || bad "$c: no ping reply"
        grep -aq '==END==' "$H" && ok "$c: script reached the end" || bad "$c: script did not finish"
        grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$H" && bad "$c: panic/exception in log" || ok "$c: no panic/exception"
        ;;
    ax179-http)
        http_run axw ax88179
        chk axw "DHCP lease over the chip" 'dhcp: ack ip=192.168.42.100'
        chk axw "HTTP status line over TCP through the chip" '200'
        chk axw "4000 octets of body arrived intact" '4000'
        grep -aq 'GET /x.txt' "$T/web-axw.log" && ok "axw: the web server saw the request" || bad "axw: the web server saw no request"
        chk axw "script reached the end" '==END=='
        panics axw
        ;;
    ax179-ecmfirst)
        nic axe ax88179-ecmfirst boot s_nic.sh
        chk axe "vendor configuration wins over ECM" 'driver=ax88179'
        nochk axe "ECM not bound" 'driver=ecm'
        net_ok axe
        ;;
    ax178a)
        nic axa ax88178a boot s_nic.sh
        chk axa "AX88178A bound to driver ax88179" 'driver=ax88179'
        net_ok axa
        ;;
    ax179-multi)
        GARGS="--inject 6" nic axm ax88179-multi boot s_nic.sh
        chk axm "bound to driver ax88179" 'driver=ax88179'
        grep -aq 'inject 6 frames' "$T/axm.gadget" && ok "axm: gadget injected a burst of 6 frames" || bad "axm: no burst"
        [ "$(grep -ac 'pack n=[2-9]' "$T/axm.gadget")" -ge 1 ] && ok "axm: at least one bulk transfer carried several packets" || bad "axm: no multi-packet transfer"
        net_ok axm
        rxmatch axm
        clean_model axm
        chk axm "no receive error counted" 'err=0'
        ;;
    ax179-late)
        GARGS="--link late" QWAIT=100 nic axl ax88179 boot s_vlate.sh
        chk axl "bound to driver ax88179" 'driver=ax88179'
        chk axl "link came up later" 'usbnet: link up 1000'
        la=$(grep -an 'usb: ax88179 ' "$T/axl.klar" | head -1 | cut -d: -f1); lb=$(grep -an 'usbnet: link up' "$T/axl.klar" | head -1 | cut -d: -f1)
        [ -n "$la" ] && [ -n "$lb" ] && [ "$la" -le "$lb" ] && ok "axl: link up reported after the bring-up line ($la <= $lb)" || bad "axl: order bring-up/link up ($la/$lb)"
        net_ok axl
        golden axl ax179 up ss
        ;;
    ax179-down)
        GARGS="--link down" QWAIT=60 nic axd ax88179 boot s_down.sh
        chk axd "bound to driver ax88179" 'driver=ax88179'
        chk axd "link reported down" 'usbnet: link down'
        chk axd "proc line says link=down" 'usbnet: ready mode=5 link=down'
        nochk axd "never up" 'usbnet: link up'
        chk axd "script reached the end" '==END=='
        panics axd
        ;;
    ax179-hot)
        nic axh ax88179 hot s_hot.sh
        chk axh "hold window ran" 'k17: hold'
        chk axh "bound to driver ax88179 after boot" 'driver=ax88179'
        net_ok axh
        ;;
    ax179-unplug)
        REPLUG_WAIT='medium=013b' nic axu ax88179 replug s_re.sh
        chk axu "bound to driver ax88179" 'driver=ax88179'
        chk axu "unplug noticed" 'usbnet: detached'
        panics axu
        ;;
    rtl8153)
        nic rt rtl8153 boot s_nic.sh
        chk rt "bound to driver rtl8153" 'driver=rtl8153'
        nochk rt "ECM not bound" 'driver=ecm'
        chk rt "MAC line from the IDR registers" 'usb: rtl8153 02:11:22:33:44:55'
        chk rt "link up at 1000" 'usbnet: link up 1000'
        chk rt "driver mode 6 ready" 'usbnet: ready mode=6 link=up'
        net_ok rt
        chk rt "DNS through the chip" '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\s*$'
        golden rt 8153a up
        clean_model rt
        rxmatch rt
        ;;
    rtl-http)
        http_run rtw rtl8153
        chk rtw "DHCP lease over the chip" 'dhcp: ack ip=192.168.42.100'
        chk rtw "HTTP status line over TCP through the chip" '200'
        chk rtw "4000 octets of body arrived intact" '4000'
        grep -aq 'GET /x.txt' "$T/web-rtw.log" && ok "rtw: the web server saw the request" || bad "rtw: the web server saw no request"
        chk rtw "script reached the end" '==END=='
        panics rtw
        ;;
    rtl8153b)
        GARGS="--rtl-family 8153b" nic rtb rtl8153 boot s_nic.sh
        chk rtb "bound to driver rtl8153" 'driver=rtl8153'
        net_ok rtb
        golden rtb 8153b up
        clean_model rtb
        ;;
    rtl8152)
        GARGS="--rtl-family 8152" nic rt2 rtl8152 boot s_nic.sh
        chk rt2 "RTL8152 bound to driver rtl8153" 'driver=rtl8153'
        net_ok rt2
        golden rt2 8152 up
        clean_model rt2
        ;;
    rtl-multi)
        GARGS="--inject 6" nic rtm rtl8153-multi boot s_nic.sh
        chk rtm "bound to driver rtl8153" 'driver=rtl8153'
        [ "$(grep -ac 'pack n=[2-9]' "$T/rtm.gadget")" -ge 1 ] && ok "rtm: at least one bulk transfer carried several packets" || bad "rtm: no multi-packet transfer"
        net_ok rtm
        rxmatch rtm
        clean_model rtm
        chk rtm "no receive error counted" 'err=0'
        ;;
    rtl-late)
        GARGS="--link late" QWAIT=100 nic rtl rtl8153 boot s_vlate.sh
        chk rtl "link came up later" 'usbnet: link up 1000'
        net_ok rtl
        golden rtl 8153a up
        ;;
    rtl-down)
        GARGS="--link down" QWAIT=60 nic rtd rtl8153 boot s_down.sh
        chk rtd "bound to driver rtl8153" 'driver=rtl8153'
        chk rtd "link reported down" 'usbnet: link down'
        chk rtd "proc line says link=down" 'usbnet: ready mode=6 link=down'
        nochk rtd "never up" 'usbnet: link up'
        chk rtd "script reached the end" '==END=='
        panics rtd
        ;;
    rtl-hot)
        nic rth rtl8153 hot s_hot.sh
        chk rth "hold window ran" 'k17: hold'
        chk rth "bound to driver rtl8153 after boot" 'driver=rtl8153'
        net_ok rth
        ;;
    rtl-unplug)
        REPLUG_WAIT='cd00 m=f' nic rtu rtl8153 replug s_re.sh
        chk rtu "bound to driver rtl8153" 'driver=rtl8153'
        chk rtu "unplug noticed" 'usbnet: detached'
        panics rtu
        ;;
    rtl-unknown-chip)
        GARGS="--rtl-family unknown" QWAIT=60 nic rtk rtl8153 boot s_down.sh
        chk rtk "bring-up refused at the version step" 'usb: rtl8153 failed step=1'
        nochk rtk "no link line" 'usbnet: link up'
        chk rtk "script reached the end" '==END=='
        panics rtk
        ;;
    rtl-unknown-id)
        QWAIT=60 nic rti rtl-unknown boot s_down.sh
        nochk rti "unknown Realtek product id not bound" 'driver=rtl8153'
        nochk rti "no NIC line" 'usbnet: ready mode=6'
        chk rti "script reached the end" '==END=='
        panics rti
        ;;
    ax-unknown-id)
        QWAIT=60 nic axk ax-unknown boot s_down.sh
        nochk axk "unknown ASIX product id not bound" 'driver=ax88179'
        nochk axk "no NIC line" 'usbnet: ready mode=5'
        chk axk "script reached the end" '==END=='
        panics axk
        ;;
    none)
        QWAIT=60 nic non ax88179 none s_down.sh
        nochk non "no driver line without a device" 'driver=ax88179'
        nochk non "no lease" 'dhcp: ack ip='
        chk non "script reached the end" '==END=='
        ;;
    two)
        XQEMU="-netdev user,id=n9 -device usb-net,netdev=n9" nic two ax88179 boot s_nic.sh
        [ "$(grep -ac 'usbnet: second adapter ignored' "$T/two.klar")" -ge 1 ] && ok "two: the second adapter is refused with a log line" || bad "two: no 'second adapter ignored' line"
        nochk two "no panic and no second ready line" 'usbnet: ready mode=.*usbnet: ready mode='
        grep -aq 'dhcp: ack ip=' "$T/two.klar" && ok "two: the first adapter keeps working (lease)" || bad "two: no lease"
        chk two "script reached the end" '==END=='
        panics two
        ;;
    esac
done
echo "USBETH: $pass ok, $fail fail"
if [ "$fail" -gt 0 ]; then
    grep -a "usb\|netdev\|nic:\|dhcp\|usbnet" "$T"/*.klar | cut -c1-170 | head -50
    for f in "$T"/*.gadget; do echo "--- $f"; tail -12 "$f"; done
    [ -n "${USBTETHER_WORK:-}" ] || cp -r "$T" /root/usbeth-fail 2>/dev/null
    exit 1
fi
exit 0
