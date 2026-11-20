echo "WINE start"
export LC_ALL=C.UTF-8 HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C WINEPREFIX=/opt/pfx PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /tmp /root
diag() {
    echo "WINE-NP diag $1 procs=$(busybox ps | busybox wc -l) pipes=$(busybox ls -l /proc/[0-9]*/fd 2>/dev/null | busybox grep -a -c pipe) sockets=$(busybox ls -l /proc/[0-9]*/fd 2>/dev/null | busybox grep -a -c socket)"
    busybox ps | busybox cut -c1-90 | busybox tail -n 25
}
stamp() { read up _ < /proc/uptime; echo "WINE-NP $1 t=$up"; }
if [ "${NP_WARM:-300}" -gt 0 ]; then
    stamp warm-begin
    WINEDEBUG=-all timeout ${NP_WARM:-300} /usr/bin/wine64 cmd /c echo warm-ok > /tmp/warm.log 2>&1 < /dev/null
    echo "WINE-NP warm rc=$? $(grep -a -c warm-ok /tmp/warm.log)"
    stamp warm-end
    diag after-warm
fi
export WAYLAND_DISPLAY=/tmp/wayland-0
if [ "${NP_EXPLORER:-1}" -gt 0 ]; then
    stamp explorer-begin
    WINEDEBUG=${NP_EXPLORER_DEBUG:-err+all} /usr/bin/wine64 explorer /desktop > /tmp/ex.log 2>&1 < /dev/null &
    sleep ${NP_EXPLORER_WAIT:-240}
    stamp explorer-wait-end
    diag after-explorer
    echo "WINE-NP explorer log bytes $(busybox wc -c < /tmp/ex.log)"
    grep -a -v preloader /tmp/ex.log | grep -a -E "${NP_GREP:-.}" | tail -${NP_EXPLORER_LINES:-40}
fi
export WINEDEBUG=${NP_DEBUG:-err+all}
stamp launch
timeout ${NP_RUN:-420} /usr/bin/wine64 notepad > /tmp/np.log 2>&1 < /dev/null &
wpid=$!
( while true; do sleep ${NP_TICK:-30}; stamp tick; busybox ps | busybox grep -a -E "wine|services|explorer|notepad|rundll" | busybox grep -a -v grep | busybox cut -c1-100 | busybox tail -n 12; echo "WINE-NP log bytes $(busybox wc -c < /tmp/np.log)"; grep -a -v preloader /tmp/np.log | tail -${NP_TICKLINES:-8}; done ) &
wait $wpid
echo "WINE-NP exit rc=$?"
grep -a -v preloader /tmp/np.log | grep -a -E "${NP_GREP:-.}" | tail -${NP_LINES:-60}
echo FX-END
