echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
up() { read u _ < /proc/uptime; echo $u; }
n=1
while [ $n -le ${FX_RUNS:-3} ]; do
    mkdir -p /tmp/p$n
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$n/user.js
    echo "FX14 run $n nslookup0 t=$(up)"
    nslookup example.com 1.1.1.1 > /dev/null 2>&1
    echo "FX14 run $n nslookup1 t=$(up)"
    echo "FX11 run $n begin t=$(up)"
    ( while [ ! -s /tmp/e$n.png ]; do sleep 0.25; done; echo "FX11 run $n png t=$(up)" ) &
    PNGW=$!
    ( i=0; while [ $i -lt 60 ]; do sleep 0.5; i=$((i+1)); echo "FX14 run $n tick t=$(up) p=$(ls /tmp/p$n | wc -l) tcp=$(wc -l < /proc/net/tcp) ff=$(pidof firefox | wc -w) to=$(pidof timeout | wc -w)"; done ) &
    TICKW=$!
    timeout 200 /usr/bin/firefox --headless --screenshot /tmp/e$n.png --window-size=1024,768 --profile /tmp/p$n https://example.com > /tmp/e$n.log 2>&1
    echo "FX11 run $n rc=$? bytes=$(wc -c < /tmp/e$n.png 2>/dev/null) t=$(up)"
    kill $PNGW $TICKW 2>/dev/null
    for p in $(pidof firefox); do kill -9 $p 2>/dev/null; done
    sleep 2
    n=$((n+1))
done
grep -a "blk" /proc/bench
echo FX-END
