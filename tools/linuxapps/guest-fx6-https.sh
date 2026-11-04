echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
cat > /tmp/js.html <<'HTML'
<html><body style="font:20px sans-serif"><h1 id="t">JS-OFF</h1><pre id="o"></pre><canvas id="c" width="300" height="100"></canvas>
<script>
var t0 = Date.now(), s = 0;
for (var i = 0; i < 3000000; i++) { s = (s + i * i) % 1000003; }
var el = document.getElementById('t'); el.textContent = 'JS-ON sum=' + s;
var rows = []; for (var j = 0; j < 40; j++) { var d = document.createElement('div'); d.textContent = 'row ' + j + ' ' + (j * 7919 % 101); document.body.appendChild(d); }
var ctx = document.getElementById('c').getContext('2d'); ctx.fillStyle = '#c00'; ctx.fillRect(10, 10, 100, 50);
document.getElementById('o').textContent = 'ms=' + (Date.now() - t0) + ' rows=' + document.getElementsByTagName('div').length + ' fetchType=' + typeof fetch + ' promise=' + typeof Promise;
</script></body></html>
HTML
up() { read u _ < /proc/uptime; echo ${u%.*}${u#*.}; }
rss() {
    tot=0
    for p in $(pidof firefox); do
        v=$(grep '^VmRSS:' /proc/$p/status 2>/dev/null | tr -dc '0-9')
        [ -n "$v" ] && tot=$((tot + v))
    done
    echo $tot
}
( while true; do echo "FX6RSS $(rss)"; sleep 10; done ) &
SP=$!
echo "FX6 wget: $(timeout 40 wget -q -O - http://93.184.216.34/ 2>&1 | head -c 80 | tr -d '
')"
run() {
    name=$1; url=$2; shift 2
    mkdir -p /tmp/p$name
    echo 'user_pref("gfx.webrender.software", true);' > /tmp/p$name/user.js
    [ -n "$NOJIT" ] && printf '%s\n' 'user_pref("javascript.options.baselinejit", false);' 'user_pref("javascript.options.ion", false);' 'user_pref("javascript.options.native_regexp", false);' 'user_pref("javascript.options.asmjs", false);' 'user_pref("javascript.options.wasm", false);' >> /tmp/p$name/user.js
    a=$(up)
    timeout 400 /usr/bin/firefox --headless --screenshot /tmp/$name.png --window-size=1024,768 --profile /tmp/p$name "$url" > /tmp/$name.log 2>&1
    rc=$?
    b=$(up)
    echo "FX6 $name rc=$rc cs=$((b - a)) bytes=$(wc -c < /tmp/$name.png 2>/dev/null)"
    tail -3 /tmp/$name.log
    if [ -s /tmp/$name.png ]; then echo "FX6IMG-BEGIN $name"; base64 /tmp/$name.png; echo "FX6IMG-END $name"; fi
}
NOJIT=1
run examplenj https://example.com
run wikinj https://en.wikipedia.org/wiki/Linux
run jsnj file:///tmp/js.html
NOJIT=
run wiki https://en.wikipedia.org/wiki/Linux
kill $SP 2>/dev/null
echo FX-END
