echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
up() { read u _ < /proc/uptime; echo $u; }
cs() { read c cu cn cs ci cw cq csq cst _ < /proc/stat; echo "FXSTAT $1 $2 user=$((cu+cn)) sys=$((cs+cq+csq)) idle=$((ci+cw))"; }
n=1
while [ $n -le 6 ]; do
    mkdir -p /tmp/p$n
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$n/user.js
    cs $n begin
    echo "FX11 run $n begin t=$(up)"
    ( while [ ! -s /tmp/e$n.png ]; do sleep 0.05; done; cs $n png; echo "FX11 run $n png t=$(up)" ) &
    PNGW=$!
    timeout 200 /usr/bin/firefox --headless --screenshot /tmp/e$n.png --window-size=1024,768 --profile /tmp/p$n 'https://example.com' > /tmp/e$n.log 2>&1
    rc=$?
    cs $n rc
    echo "FX11 run $n rc=$rc bytes=$(wc -c < /tmp/e$n.png 2>/dev/null) t=$(up)"
    echo "FXCHILD $n $(cut -d' ' -f16,17 /proc/$$/stat)"
    kill $PNGW 2>/dev/null
    for p in $(pidof firefox); do kill -9 $p 2>/dev/null; done
    sleep 2
    n=$((n+1))
done
echo FX-END
