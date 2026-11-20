echo "WINE start"
export LC_ALL=C.UTF-8 HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C WINEPREFIX=${WARM_PREFIX:-/opt/pfx} WINEDEBUG=-all PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /tmp /root
read t0 _ < /proc/uptime
echo "WINE-WARM begin t=$t0"
timeout ${WARM_TMO:-900} /usr/bin/wine64 cmd /c echo warm-ok > /tmp/warm.log 2>&1 < /dev/null
echo "WINE-WARM rc=$? $(grep -a -c warm-ok /tmp/warm.log)"
read t1 _ < /proc/uptime
echo "WINE-WARM end t=$t1"
echo FX-END
