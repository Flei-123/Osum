echo "XR start"
export HOME=/root
mkdir -p /root /tmp
/opt/xr/xrprobe screen
mkdir -p /etc
echo scheme=probe > /etc/theme.conf
sed 's/^/XR-THEME-BEFORE /' /etc/theme.conf
mkdir -p /var/probe/.config/freeviewer
n=0
while [ $n -lt 12 ]; do
    echo "grabber: $n frames grabbed, probe" >> /var/probe/.config/freeviewer/capture.log
    sleep 1
    n=$((n + 1))
done
sed 's/^/XR-THEME-APPEND /' /etc/theme.conf
/opt/xr/xrprobe grabbench 10
echo xr-udp-probe | nc -u -w1 10.0.2.2 @UDPPORT@
export FV_RELAY=ws://10.0.2.2:@RELAYPORT@/fv/ws FV_ALLOW_INSECURE_RELAY=1 FV_PASSWORD=xrpass FV_NOSTUN=1
/opt/xr/freeviewer-host --headless --state-file /tmp/state --home /root > /tmp/host.log 2>&1 &
HP=$!
i=0
ID=
while [ $i -lt @HOSTSECS@ ]; do
    ID=$(grep -o 'ID [0-9][0-9]*' /tmp/host.log | sed -n 1p)
    if [ -n "$ID" ]; then
        echo "XR-$ID"
        break
    fi
    sleep 1
    i=$((i + 1))
done
t=0
while [ $t -lt @TAILSECS@ ]; do
    sed 's/^/XR-STATE /' /tmp/state 2>/dev/null
    sleep 5
    t=$((t + 5))
done
/opt/xr/xrprobe grabbench 5
echo "XR-HOSTLOG-BEGIN"
cat /tmp/host.log
echo "XR-HOSTLOG-END"
kill $HP 2>/dev/null
sleep 2
sed 's/^/XR-THEME-AFTER /' /etc/theme.conf
echo XR-END
