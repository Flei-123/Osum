echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
[ -n "${FXLOG:-}" ] && export MOZ_LOG="$FXLOG"
up() { read u _ < /proc/uptime; echo $u; }
[ -n "${FX_PROBES:-}" ] && echo "FX11 nslookup: $(timeout 20 nslookup example.com 2>&1 | tr '\n' ' ' | head -c 200)"
[ -n "${FX_PROBES:-}" ] && echo "FX11 wget-https: $(timeout 60 wget -q -O - https://example.com/ 2>&1 | head -c 40 | tr -d '\n')"
n=1
while [ $n -le ${FX_RUNS:-2} ]; do
    mkdir -p /tmp/p$n
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$n/user.js
    echo "FX11 run $n begin t=$(up)"
    timeout ${FX_TMO:-200} /usr/bin/firefox --headless --screenshot /tmp/e$n.png --window-size=1024,768 --profile /tmp/p$n ${FX_URL:-https://example.com} > /tmp/e$n.log 2>&1
    echo "FX11 run $n rc=$? bytes=$(wc -c < /tmp/e$n.png 2>/dev/null) t=$(up)"
    grep -a "user fault\|SEGV\|Segmentation" /tmp/e$n.log | head -3
    if [ ! -s /tmp/e$n.png ]; then
        echo "FX11 run $n tail:"
        grep -a "nsHostResolver\|nsSocketTransport\|pipnss" /tmp/e$n.log | tail -${FX_TAIL:-25} | cut -c1-220
    fi
    for p in $(pidof firefox); do kill -9 $p 2>/dev/null; done
    sleep 2
    n=$((n+1))
done
echo FX-END
