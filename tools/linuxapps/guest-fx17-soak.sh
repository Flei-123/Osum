echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
up() { read u _ < /proc/uptime; echo $u; }
n=1
while [ $n -le 16 ]; do
    mkdir -p /tmp/p$n
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$n/user.js
    echo "FX11 run $n begin t=$(up)"
    ( while [ ! -s /tmp/e$n.png ]; do sleep 0.25; done; echo "FX11 run $n png t=$(up)" ) &
    PNGW=$!
    ( sleep 1; for q in $(pidof firefox); do grep -a "libxul\|scudo\|libc.so" /proc/$q/maps | head -4; echo "maps-pid $q"; break; done ) &
    timeout 200 /usr/bin/firefox --headless --screenshot /tmp/e$n.png --window-size=1024,768 --profile /tmp/p$n https://example.com > /tmp/e$n.log 2>&1
    echo "FX11 run $n rc=$? bytes=$(wc -c < /tmp/e$n.png 2>/dev/null) t=$(up)"
    kill $PNGW 2>/dev/null
    tail -c 600 /tmp/e$n.log
    for p in $(pidof firefox); do kill -9 $p 2>/dev/null; done
    sleep 1
    n=$((n+1))
done
echo FX-END
