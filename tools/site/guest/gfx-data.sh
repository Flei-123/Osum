echo "FX start"
echo "CPUS proc=$(grep -c ^processor /proc/cpuinfo 2>/dev/null) osum=$(grep -o "cpus_online=[0-9]*" /proc/cpus 2>/dev/null)"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
up() { read u _ < /proc/uptime; echo $u; }
n=1
while [ $n -le ${FX_RUNS:-4} ]; do
    mkdir -p /tmp/p$n
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$n/user.js
    echo "FX11 run $n begin t=$(up)"
    ( while [ ! -s /tmp/e$n.png ]; do sleep 0.25; done; echo "FX11 run $n png t=$(up)" ) &
    PNGW=$!
    timeout 200 /usr/bin/firefox --headless --screenshot /tmp/e$n.png --window-size=1024,768 --profile /tmp/p$n 'data:text/html,hello' > /tmp/e$n.log 2>&1
    echo "FX11 run $n rc=$? bytes=$(wc -c < /tmp/e$n.png 2>/dev/null) t=$(up)"
    kill $PNGW 2>/dev/null
    for p in $(pidof firefox); do kill -9 $p 2>/dev/null; done
    sleep 2
    n=$((n+1))
done
echo FX-END
