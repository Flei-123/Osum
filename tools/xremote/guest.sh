echo "XR start"
export HOME=/root
mkdir -p /root /tmp
/opt/xr/freeviewer-host --version
echo "XR1 rc=$?"
/opt/xr/xrprobe screen
/opt/xr/xrprobe grab
echo "XR2 rc=$?"
/opt/xr/xrprobe input
export FV_RELAY=ws://10.0.2.2:@RELAYPORT@/fv/ws FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1 FV_PASSWORD=xrpass
timeout @HOSTSECS@ /opt/xr/freeviewer-host --headless > /tmp/host.log 2>&1 &
HP=$!
sleep 20
echo XR-EARLY-BEGIN
cat /tmp/host.log
echo XR-EARLY-END
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
sleep @SESSIONSECS@
echo "XR-HOSTLOG-BEGIN"
cat /tmp/host.log
echo "XR-HOSTLOG-END"
/opt/xr/xrprobe input
/opt/xr/xrprobe screen
kill $HP
echo XR-END
