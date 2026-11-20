echo "WINE start"
export LC_ALL=C.UTF-8 HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C WINEPREFIX=/tmp/pfx PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /tmp /root
up() { read u _ < /proc/uptime; echo "WINE uptime $u $1"; }
up boot
WINEDEBUG=${TRACE_CHANNELS:-+server,+timestamp,err+all} /usr/bin/wine64 wineboot --init > /tmp/o.boot 2>&1 < /dev/null &
wpid=$!
sleep ${HANG_WAIT:-240}
up dump
ps
for p in /proc/[0-9]*; do
    n=${p#/proc/}
    for t in $p/task/*; do
        read -r line < $t/stat
        echo "TASK $n ${t#$p/task/} $line"
    done
done 2>/dev/null | grep -a -E "wine|services|rundll|explorer|winedevice" | cut -c1-160
grep -a -v preloader /tmp/o.boot | tail -${WINE_LINES:-300}
kill $wpid
echo FX-END
