echo "FX start"
export MOZ_LOG="${FX7_MOZLOG:-WidgetKeyboard:5,Widget:5}"
export MOZ_LOG_FILE=/tmp/e.log
[ -n "${FX7_WLDEBUG:-}" ] && export WAYLAND_DEBUG=1
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 MOZ_ENABLE_WAYLAND=1 GDK_BACKEND=wayland MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1 FONTCONFIG_FILE=/etc/fonts/fonts.conf
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo 'user_pref("browser.shell.checkDefaultBrowser", false);' >> /tmp/p/user.js
echo 'user_pref("browser.dom.window.dump.enabled", true);' >> /tmp/p/user.js
cat > /tmp/in.html <<'HTML'
<html><body style="margin:0"><input id="i" autofocus style="font-size:30px;width:400px"><p id="t" style="position:absolute;top:60px;left:0;margin:0;font-size:30px;white-space:nowrap">alpha beta gamma delta</p><a id="l" href="in.html?nav" style="display:block;height:2000px;background:#eee">link</a><div id="b" style="position:fixed;right:0;bottom:0;width:600px;height:300px;display:none"></div><div style="height:6000px;background:linear-gradient(#fff,#06c)">tall</div>
<script>
addEventListener('keydown', function (e) { dump('FXKEY ' + e.key + ' shift=' + e.shiftKey + '\n'); });
addEventListener('contextmenu', function (e) { e.preventDefault(); dump('FXCTX ' + e.clientX + ',' + e.clientY + '\n'); });
addEventListener('mousedown', function (e) { dump('FXDOWN ' + e.button + '\n'); });
addEventListener('wheel', function (e) { dump('FXWHEEL ' + e.deltaY + ' mode=' + e.deltaMode + '\n'); });
addEventListener('mousemove', function (e) { dump('FXMOVE ' + e.clientX + ',' + e.clientY + '\n'); });
addEventListener('scroll', function () { dump('FXSCROLL ' + scrollY + '\n'); });
addEventListener('click', function (e) { dump('FXCLICK ' + e.clientX + ',' + e.clientY + '\n'); });
document.getElementById('i').addEventListener('input', function (e) { dump('FXINPUT ' + e.target.value + '\n'); });
document.addEventListener('mousedown', function (e) { dump('FXDOWN ' + e.clientX + ',' + e.clientY + '\n'); });
document.addEventListener('mouseup', function () { setTimeout(function () { var s = String(getSelection()); if (s) dump('FXDRAG ' + s + '\n'); }, 50); });
addEventListener('dblclick', function () { dump('FXDBL ' + getSelection() + '\n'); });
addEventListener('resize', function () { dump('FXRESIZE ' + innerWidth + 'x' + innerHeight + '\n'); });
var query = location.search;
var marks = { '?nav': ['FXNAV', '#0000c8'], '?u': ['FXURL', '#00c800'] };
dump('FXLOAD ' + document.getElementsByTagName('div').length + ' h=' + document.body.scrollHeight + '\n');
dump('FXSIZE ' + innerWidth + 'x' + innerHeight + '\n');
if (marks[query]) {
    document.getElementById('b').style.cssText += ';display:block;background:' + marks[query][1];
    dump(marks[query][0] + ' ' + query + '\n');
}
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
echo "FX7 launch t=$(up)"
/usr/lib/firefox/firefox --no-remote --profile /tmp/p file:///tmp/in.html > /tmp/fx3.log 2>&1 &
( while true; do echo "FX7 t=$(up) rss=$(rss) shm=$(grep -a "^ShmObjects:" /proc/meminfo | tr -dc 0-9) usock=$(grep -a "^UnixSockets:" /proc/meminfo | tr -dc 0-9) nav=$(grep -ac '^FXNAV ' /tmp/fx3.log) url=$(grep -ac '^FXURL ' /tmp/fx3.log) pos=$(grep -a '^FXMOVE ' /tmp/fx3.log | tail -n 1) last=$(grep -a '^FX[A-Z]* ' /tmp/fx3.log | tail -n 1)"; sleep 10; done ) &
waited=0
until [ "$(grep -ac '^FXURL ' /tmp/fx3.log)" -ge 1 ] || [ "$waited" -ge "${FX7_WAIT:-420}" ]; do sleep 5; waited=$((waited + 5)); done
if [ "$(grep -ac '^FXURL ' /tmp/fx3.log)" -ge 1 ]; then
    tail_waited=0
    until [ "$(grep -ac '^FXKEY F9' /tmp/fx3.log)" -ge 1 ] || [ "$tail_waited" -ge "${FX7_TAIL:-300}" ]; do sleep 2; tail_waited=$((tail_waited + 2)); done
fi
echo "FX7 all events:"
grep -a '^FX[A-Z]* ' /tmp/fx3.log | grep -av '^FXMOVE ' | head -${FX7_EVENTS:-400}
echo "FX7 wayland axis:"
grep -a "pointer.*axis\|wl_pointer@[0-9]*\.\(enter\|leave\|motion\|frame\)" /tmp/fx3.log | tail -${FX7_AXTAIL:-30} | cut -c1-200
echo "FX7 widget log:"
grep -a -i "key\|focus\|enter\|leave\|seat" /tmp/fx3.log /tmp/e.log* | grep -av "FX[A-Z]* " | tail -${FX7_LOGTAIL:-40} | cut -c1-200
echo "FX7 logsize: $(wc -c < /tmp/fx3.log) fx3, $(wc -c /tmp/e.log* | tail -n 1)"
echo "FX7 fx3 tail:"
tail -n 15 /tmp/fx3.log | cut -c1-200
echo FX-END
