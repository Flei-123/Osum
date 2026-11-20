echo "WINE start"
export LC_ALL=C.UTF-8 HOME=/root TERM=xterm XDG_RUNTIME_DIR=/tmp LANG=C WINEDEBUG=-all WINEPREFIX=/tmp/pfx PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
mkdir -p /tmp /root
t() {
    n=$1; want=$2; shift 2
    echo "WINE $n begin"
    timeout ${WINE_TMO:-240} "$@" > /tmp/o.$n 2>&1 < /dev/null
    rc=$?
    if [ $rc -eq 0 ] && grep -q -- "$want" /tmp/o.$n; then echo "WINE-RESULT $n ok"; else echo "WINE-RESULT $n red rc=$rc want=$want"; fi
    head -${WINE_LINES:-8} /tmp/o.$n
}
t version wine-11 /usr/bin/wine --version
t server-version "Wine 11.0" /usr/bin/wineserver --version
t console-echo hello-from-wine env WINEDEBUG=err+all,warn+virtual /usr/bin/wine64 cmd /c echo hello-from-wine
echo FX-END
