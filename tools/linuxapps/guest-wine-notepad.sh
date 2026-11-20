echo "WINE start"
export LC_ALL=C.UTF-8 HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C WINEPREFIX=/opt/pfx PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /tmp /root
stamp() { read up _ < /proc/uptime; echo "WINE-NP $1 t=$up"; }
if [ "${NP_WARM:-300}" -gt 0 ]; then
    stamp warm-begin
    WINEDEBUG=-all timeout ${NP_WARM:-300} /usr/bin/wine64 cmd /c echo warm-ok > /tmp/warm.log 2>&1 < /dev/null
    echo "WINE-NP warm rc=$? $(grep -a -c warm-ok /tmp/warm.log)"
    stamp warm-end
fi
export WAYLAND_DISPLAY=/tmp/wayland-0 WINEDEBUG=${NP_DEBUG:-err+all}
stamp launch
timeout ${NP_RUN:-420} /usr/bin/wine64 notepad > /tmp/np.log 2>&1 < /dev/null &
wpid=$!
( while true; do sleep ${NP_TICK:-30}; stamp tick; busybox ps | busybox grep -a -E "wine|services|explorer|notepad|rundll" | busybox grep -a -v grep | busybox cut -c1-100 | busybox tail -n 12; echo "WINE-NP log bytes $(busybox wc -c < /tmp/np.log)"; grep -a -v preloader /tmp/np.log | tail -${NP_TICKLINES:-8}; done ) &
wait $wpid
echo "WINE-NP exit rc=$?"
grep -a -v preloader /tmp/np.log | tail -${NP_LINES:-60}
echo FX-END
