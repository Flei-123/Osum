B=/bin/busybox
export HOME=/root
$B mkdir -p /root /tmp /run /var/log
CONF=/etc/xremote.conf
INFO=/run/xremote.info
STATE=/run/xremote.state
LOG=/var/log/xremote.log
PKG=/apps/xremote.prog/bin/freeviewer-host
kv() { while IFS== read -r k v; do [ "$k" = "$2" ] && { echo "$v"; return; }; done < "$1"; }
nap() { n=$1; while [ $n -gt 50 ]; do $B sleep 50; n=$((n - 50)); done; [ $n -gt 0 ] && $B sleep $n; }
ex() { [ -e "$1" ] && echo 1 || echo 0; }
enable() { echo "enabled=1" > $CONF; echo "relay=ws://10.0.2.2:@RELAYPORT@/fv/ws" >> $CONF; }
wait_id() {
    i=0
    while [ $i -lt @HOSTSECS@ ]; do
        [ -n "$(kv $STATE id)" ] && return
        $B sleep 1
        i=$((i + 1))
        [ $((i % 30)) = 0 ] && { echo "SV-WAIT $i state=$(ex $STATE) log=$(ex $LOG)"; $B tail -n 4 $LOG 2>/dev/null; }
    done
}
echo "SV-PKG host=$(ex $PKG) ld=$(ex /apps/xremote.prog/lib/ld-musl-x86_64.so.1) gcc=$(ex /apps/xremote.prog/lib/libgcc_s.so.1)"
echo "SV-BEFORE conf=$(ex $CONF) pw=$(ex /run/xremote.pw) info=$(ex $INFO) log=$(ex $LOG)"
echo "SV-PHASE A"
$B sleep 8
echo "SV-A service=$(kv $INFO service) password=$(kv $INFO password) pw=$(ex /run/xremote.pw) state=$(ex $STATE) log=$(ex $LOG)"
#DBG echo "SV-DBG-BEGIN"
#DBG $B nc -w 3 10.0.2.2 @RELAYPORT@ < /dev/null; echo "SV-DBG-NC rc=$?"
#DBG ( export FV_RELAY=ws://10.0.2.2:@RELAYPORT@/fv/ws FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1 FV_PASSWORD=oldpw123 HOME=/tmp/oldhome; $B mkdir -p /tmp/oldhome; /opt/xr/freeviewer-old --headless > /tmp/old.log 2>&1 & OP=$!; $B sleep 15; echo "SV-DBG-OLD"; $B cat /tmp/old.log; kill $OP )
#DBG echo secretpw1 > /tmp/dbg.pw
#DBG /apps/xremote.prog/lib/ld-musl-x86_64.so.1 --library-path /apps/xremote.prog/lib /apps/xremote.prog/bin/freeviewer-host --password-file /tmp/dbg.pw --state-file /tmp/dbg.state --home /tmp/dbghome --no-p2p --relay ws://10.0.2.2:@RELAYPORT@/fv/ws --insecure-relay > /tmp/dbg.log 2>&1 &
#DBG DP=$!
#DBG $B sleep 25
#DBG echo "SV-DBG-STATE $($B cat /tmp/dbg.state 2>&1 | $B tr '\n' ' ')"
#DBG $B cat /tmp/dbg.log
#DBG kill $DP
#DBG echo "SV-DBG-END"
echo "SV-PHASE B"
enable
$B sleep 3
echo "SV-B0 service=$(kv $INFO service)"
wait_id
ID=$(kv $STATE id)
PW=$(kv $INFO password)
PWF=$($B cat /run/xremote.pw 2>/dev/null)
echo "SV-ID $ID"
echo "SV-PW $PW"
echo "SV-B service=$(kv $INFO service) pwlen=${#PW} samepw=$([ "$PW" = "$PWF" ] && echo 1 || echo 0) status=$(kv $STATE status)"
echo "SV-WINDOW1"
nap @WINDOW@
echo "SV-LOG1-BEGIN"
$B cat $LOG
echo "SV-LOG1-END"
echo "SV-PHASE C"
echo "enabled=0" > $CONF
$B sleep 8
echo "SV-C service=$(kv $INFO service) password=$(kv $INFO password) pw=$(ex /run/xremote.pw) state=$(ex $STATE)"
echo "SV-DISABLED-DONE"
nap @AFTERSECS@
echo "SV-PHASE D"
$B mv $PKG $PKG.off
enable
$B sleep 8
echo "SV-D service=$(kv $INFO service) password=$(kv $INFO password) pw=$(ex /run/xremote.pw) state=$(ex $STATE)"
echo "SV-PHASE E"
$B mv $PKG.off $PKG
$B sleep 6
wait_id
ID2=$(kv $STATE id)
PW2=$(kv $INFO password)
echo "SV-ID2 $ID2"
echo "SV-PW2 $PW2"
echo "SV-E service=$(kv $INFO service) pwlen=${#PW2} newpw=$([ "$PW2" != "$PW" ] && echo 1 || echo 0) sameid=$([ "$ID2" = "$ID" ] && echo 1 || echo 0)"
echo "SV-WINDOW2"
nap @WINDOW2@
echo "enabled=0" > $CONF
$B sleep 8
echo "SV-F service=$(kv $INFO service) pw=$(ex /run/xremote.pw) state=$(ex $STATE)"
echo SV-END
