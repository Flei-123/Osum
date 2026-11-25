echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
up() { read u _ < /proc/uptime; echo $u; }
snap() {
    echo "FX19 run $1 $2 t=$(up)"
    grep -a -E '^(blk\.|tickgap\.sum|lock\.[0-9]+ |mmlock\.[0-9]+ )' /proc/bench | sed "s/^/FX19 $1 $2 /"
    sed "s/^/FX19 $1 $2 /" /proc/vfscache
}
n=1
while [ $n -le ${FX_RUNS:-5} ]; do
    mkdir -p /tmp/p$n
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$n/user.js
    snap $n begin
    echo "FX11 run $n begin t=$(up)"
    ( while [ ! -s /tmp/e$n.png ]; do sleep 0.25; done; echo "FX11 run $n png t=$(up)"; snap $n png ) &
    PNGW=$!
    timeout 200 /usr/bin/firefox --headless --screenshot /tmp/e$n.png --window-size=1024,768 --profile /tmp/p$n 'https://example.com' > /tmp/e$n.log 2>&1
    echo "FX11 run $n rc=$? bytes=$(wc -c < /tmp/e$n.png 2>/dev/null) t=$(up)"
    snap $n rc
    kill $PNGW 2>/dev/null
    for p in $(pidof firefox); do kill -9 $p 2>/dev/null; done
    sleep 2
    n=$((n+1))
done
echo FX-END
