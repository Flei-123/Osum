B=/bin/busybox
export HOME=/root
$B mkdir -p /root /tmp /run /var/log
CONF=/etc/xremote.conf
SECRET=/etc/xremote.secret
HOMEID=/var/xremote/.config/freeviewer/identity.txt
INFO=/run/xremote.info
STATE=/run/xremote.state
LOG=/var/log/xremote.log
PKG=/apps/xremote.osp/bin/freeviewer-host
kv() { while IFS== read -r k v; do [ "$k" = "$2" ] && { echo "$v"; return; }; done < "$1"; }
nap() { n=$1; while [ $n -gt 50 ]; do $B sleep 50; n=$((n - 50)); done; [ $n -gt 0 ] && $B sleep $n; }
ex() { [ -e "$1" ] && echo 1 || echo 0; }
enable() { echo "enabled=1" > $CONF; echo "relay=ws://10.0.2.2:@RELAYPORT@/fv/ws" >> $CONF; }
act_q() { /bin/act "$@" 2>&1 | $B tr '\n' ' '; }
bus_set() {
    echo "SV-BUS-SET $1 $(act_q call settings.set key=remote.enabled value=$1)"
    echo "SV-BUS-CONFIRM $1 $(act_q confirm last)"
    $B sleep 8
}
bus_key() {
    echo "SV-BUS-SET $1=$2 $(act_q call settings.set key=$1 value=$2)"
    $B sleep 8
}
perm() { $B ls -l "$1" 2>/dev/null | $B cut -c1-10; }
wait_id() {
    i=0
    while [ $i -lt @HOSTSECS@ ]; do
        [ -n "$(kv $STATE id)" ] && return
        $B sleep 1
        i=$((i + 1))
        [ $((i % 30)) = 0 ] && { echo "SV-WAIT $i state=$(ex $STATE) log=$(ex $LOG)"; $B tail -n 4 $LOG 2>/dev/null; }
    done
}
echo "SV-PKG host=$(ex $PKG) ld=$(ex /apps/xremote.osp/lib/ld-musl-x86_64.so.1) gcc=$(ex /apps/xremote.osp/lib/libgcc_s.so.1)"
echo "SV-BEFORE conf=$(ex $CONF) pw=$(ex /run/xremote.pw) info=$(ex $INFO) log=$(ex $LOG)"
echo "SV-PHASE A"
$B sleep 8
echo "SV-A service=$(kv $INFO service) password=$(kv $INFO password) pw=$(ex /run/xremote.pw) state=$(ex $STATE) log=$(ex $LOG)"
#DBG echo "SV-DBG-BEGIN"
#DBG $B nc -w 3 10.0.2.2 @RELAYPORT@ < /dev/null; echo "SV-DBG-NC rc=$?"
#DBG ( export FV_RELAY=ws://10.0.2.2:@RELAYPORT@/fv/ws FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1 FV_PASSWORD=oldpw123 HOME=/tmp/oldhome; $B mkdir -p /tmp/oldhome; /opt/xr/freeviewer-old --headless > /tmp/old.log 2>&1 & OP=$!; $B sleep 15; echo "SV-DBG-OLD"; $B cat /tmp/old.log; kill $OP )
#DBG echo secretpw1 > /tmp/dbg.pw
#DBG /apps/xremote.osp/lib/ld-musl-x86_64.so.1 --library-path /apps/xremote.osp/lib /apps/xremote.osp/bin/freeviewer-host --password-file /tmp/dbg.pw --state-file /tmp/dbg.state --home /tmp/dbghome --no-p2p --relay ws://10.0.2.2:@RELAYPORT@/fv/ws --insecure-relay > /tmp/dbg.log 2>&1 &
#DBG DP=$!
#DBG $B sleep 25
#DBG echo "SV-DBG-STATE $($B cat /tmp/dbg.state 2>&1 | $B tr '\n' ' ')"
#DBG $B cat /tmp/dbg.log
#DBG kill $DP
#DBG echo "SV-DBG-END"
echo "SV-RIGHTS $(/bin/apprights get xremote 2>&1 | $B tr '\n' ' ')"
echo "SV-BUS-GET0 enabled=$(act_q call settings.get key=remote.enabled) service=$(act_q call settings.get key=remote.service)"
echo "SV-PHASE B"
echo "relay=ws://10.0.2.2:@RELAYPORT@/fv/ws" > $CONF
bus_set true
$B sleep 3
echo "SV-B0 service=$(kv $INFO service)"
wait_id
ID=$(kv $STATE id)
PW=$(kv $INFO password)
PWF=$($B cat /run/xremote.pw 2>/dev/null)
echo "SV-ID $ID"
echo "SV-PW $PW"
echo "SV-B service=$(kv $INFO service) pwlen=${#PW} samepw=$([ "$PW" = "$PWF" ] && echo 1 || echo 0) status=$(kv $STATE status)"
echo "SV-MIG seed=$($B cat $HOMEID 2>/dev/null) old=$(ex /run/xremote) perms=$(perm $HOMEID)"
echo "SV-BUS-GET1 id=$(act_q call settings.get key=remote.id)"
echo "SV-BUS-GET2 password=$(act_q call settings.get key=remote.password)"
echo "SV-BUS-GET3 status=$(act_q call settings.get key=remote.status)"
echo "SV-BUS-GET4 enabled=$(act_q call settings.get key=remote.enabled) conf=$($B tr '\n' ' ' < $CONF)"
echo "SV-WINDOW1"
nap @WINDOW@
echo "SV-LOG1-BEGIN"
$B cat $LOG
echo "SV-LOG1-END"
echo "SV-PHASE C"
bus_set false
echo "SV-BUS-GET5 enabled=$(act_q call settings.get key=remote.enabled) conf=$($B tr '\n' ' ' < $CONF)"
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
echo "SV-PHASE H"
bus_key remote.fixedpw short
echo "SV-H0 secret=$(ex $SECRET)"
bus_key remote.fixedpw Sup3rS3cret
echo "SV-H1 secret=$(ex $SECRET) perm=$(perm $SECRET) mode=$(kv $INFO mode)"
bus_key remote.fixed true
$B sleep 6
wait_id
ID3=$(kv $STATE id)
PW3=$(kv $INFO password)
PWF3=$($B cat /run/xremote.pw 2>/dev/null)
echo "SV-ID3 $ID3"
echo "SV-PW3 $PW3"
echo "SV-H service=$(kv $INFO service) mode=$(kv $INFO mode) pw=$PW3 samepw=$([ "$PW3" = "$PWF3" ] && echo 1 || echo 0) sameid=$([ "$ID3" = "$ID" ] && echo 1 || echo 0) identity=$(ex $HOMEID) oldhome=$(ex /run/xremote)"
echo "SV-H-PERMS secret=$(perm $SECRET) pw=$(perm /run/xremote.pw) info=$(perm $INFO) home=$($B ls -ld /var/xremote | $B cut -c1-10)"
echo "SV-BUS-GETPW $(act_q call settings.get key=remote.fixedpw)"
echo "SV-BUS-GETMODE $(act_q call settings.get key=remote.mode)"
echo "SV-BUS-GETFIXED $(act_q call settings.get key=remote.fixed) conf=$($B tr '\n' ' ' < $CONF)"
nap @WINDOW2@
bus_key remote.fixed false
$B sleep 6
wait_id
ID4=$(kv $STATE id)
PW4=$(kv $INFO password)
echo "SV-I mode=$(kv $INFO mode) service=$(kv $INFO service) pwlen=${#PW4} differs=$([ "$PW4" != "$PW3" ] && echo 1 || echo 0) secretkept=$(ex $SECRET) sameid=$([ "$ID4" = "$ID" ] && echo 1 || echo 0)"
nap @WINDOW2@
echo "enabled=0" > $CONF
$B sleep 8
echo "SV-F service=$(kv $INFO service) pw=$(ex /run/xremote.pw) state=$(ex $STATE)"
if [ @REALRELAY@ = 1 ]; then
    echo "SV-PHASE G"
    echo "enabled=1" > $CONF
    $B sleep 3
    wait_id
    echo "SV-G service=$(kv $INFO service) id=$(kv $STATE id) status=$(kv $STATE status)"
    $B tail -n 3 $LOG
    echo "enabled=0" > $CONF
    $B sleep 8
fi
echo SV-END
