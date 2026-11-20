export HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /tmp /root
t() {
    n=$1; want=$2; shift 2
    echo "APPS $n begin"
    timeout ${APP_TMO:-90} "$@" > /tmp/o.$n 2>&1 < /dev/null
    rc=$?
    if [ $rc -eq 0 ] && grep -q -- "$want" /tmp/o.$n; then echo "APPS-RESULT $n ok"; else echo "APPS-RESULT $n red rc=$rc want=$want"; tail -${APP_LINES:-8} /tmp/o.$n | sed "s/^/APPS-OUT $n: /"; fi
}
