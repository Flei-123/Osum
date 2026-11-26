echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
up() { read u _ < /proc/uptime; echo $u; }
upi() { read u _ < /proc/uptime; echo ${u%.*}; }
hang_dump() {
    echo "FX-HANG kind=$1 run=$2 t=$(up)"
    ps
    cat /proc/bench > /dev/null
    echo "FX-HANG-DUMP1-DONE"
    sleep 5
    cat /proc/bench > /dev/null
    echo "FX-HANG-DUMP2-DONE"
    grep -a "^tlb\." /proc/bench
    sleep ${FX_HANG_HOLD:-3000}
    echo FX-END
}
watch() {
    wn=$1
    t0=$(upi)
    tpng=0
    while [ ! -e /tmp/fin$wn ]; do
        sleep 3
        now=$(upi)
        if [ -s /tmp/e$wn.png ]; then
            [ $tpng -eq 0 ] && tpng=$now
            if [ $((now - tpng)) -ge ${FX_HANG_EXIT:-45} ]; then
                hang_dump exit $wn
                return
            fi
        elif [ $((now - t0)) -ge ${FX_HANG_START:-60} ]; then
            hang_dump start $wn
            return
        fi
    done
}
n=1
while [ $n -le ${FX_RUNS:-6} ]; do
    mkdir -p /tmp/p$n
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$n/user.js
    echo "FX11 run $n begin t=$(up)"
    ( while [ ! -s /tmp/e$n.png ]; do sleep 0.25; done; echo "FX11 run $n png t=$(up)" ) &
    PNGW=$!
    watch $n &
    WDOG=$!
    timeout ${FX_TIMEOUT:-3000} /usr/bin/firefox --headless --screenshot /tmp/e$n.png --window-size=1024,768 --profile /tmp/p$n https://example.com > /tmp/e$n.log 2>&1
    echo "FX11 run $n rc=$? bytes=$(wc -c < /tmp/e$n.png 2>/dev/null) t=$(up)"
    : > /tmp/fin$n
    kill $PNGW 2>/dev/null
    tail -c 400 /tmp/e$n.log
    for p in $(pidof firefox); do kill -9 $p 2>/dev/null; done
    sleep 2
    n=$((n+1))
done
grep -a "^tlb\.3[01] " /proc/bench
echo FX-END
