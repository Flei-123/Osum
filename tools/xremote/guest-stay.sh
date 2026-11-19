echo "XR start"
export HOME=/root
mkdir -p /root /tmp
export FV_RELAY=ws://10.0.2.2:@RELAYPORT@/fv/ws FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1 FV_PASSWORD=xrpass
/opt/xr/freeviewer-host --headless > /tmp/host.log 2>&1 &
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
n=0
while [ $n -lt @STAYSECS@ ]; do
    sleep 30
    n=$((n + 30))
    echo "XR-TICK $n alive=$(kill -0 $HP 2>/dev/null && echo 1 || echo 0)"
done
sleep @TAILSECS@
echo "XR-HOSTLOG-BEGIN"
grep -v '^ID ' /tmp/host.log
echo "XR-HOSTLOG-END"
kill $HP 2>/dev/null
echo XR-END
