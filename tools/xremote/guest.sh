echo "XR start"
export HOME=/root
mkdir -p /root /tmp
/opt/xr/freeviewer-host --version
echo "XR1 rc=$?"
/opt/xr/xrprobe screen
/opt/xr/xrprobe heads
/opt/xr/xrprobe grab
echo "XR2 rc=$?"
/opt/xr/xrprobe input
/opt/xr/xrprobe wheel
/opt/xr/xrprobe clipget
/opt/xr/xrprobe input
export FV_RELAY=ws://10.0.2.2:@RELAYPORT@/fv/ws FV_ALLOW_INSECURE_RELAY=1 FV_NOP2P=1 FV_PASSWORD=xrpass
/opt/xr/xrprobe env
/opt/xr/freeviewer-host --headless > /tmp/host.log 2>&1 &
HP=$!
sleep 20
if kill -0 $HP 2>/dev/null; then echo XR-ALIVE; else echo XR-DEAD; wait $HP; echo "XR-HOSTRC $?"; fi
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
(while true; do printf '%100s%s\n' '' XR-RIGHT-MARK; sleep 1; done) &
MP=$!
sleep 3
/opt/xr/xrprobe headlit
/opt/xr/xrprobe clipwait FV-CLIP- @CLIPSECS@
/opt/xr/xrprobe clipbig 5000
sleep @TAILSECS@
/opt/xr/xrprobe headlit
echo "XR-HOSTLOG-BEGIN"
cat /tmp/host.log
echo "XR-HOSTLOG-END"
/opt/xr/xrprobe input
/opt/xr/xrprobe screen
kill $MP 2>/dev/null
kill $HP 2>/dev/null
echo XR-END
