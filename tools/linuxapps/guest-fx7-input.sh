echo "FX start"
export MOZ_LOG="${FX7_MOZLOG:-WidgetKeyboard:5,Widget:5}"
export MOZ_LOG_FILE=/tmp/e.log
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 MOZ_ENABLE_WAYLAND=1 GDK_BACKEND=wayland MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1 FONTCONFIG_FILE=/etc/fonts/fonts.conf
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo 'user_pref("browser.shell.checkDefaultBrowser", false);' >> /tmp/p/user.js
echo 'user_pref("browser.dom.window.dump.enabled", true);' >> /tmp/p/user.js
cat > /tmp/in.html <<'HTML'
<html><body style="margin:0"><input id="i" autofocus style="font-size:30px;width:400px"><div style="height:6000px;background:linear-gradient(#fff,#06c)">tall</div>
<script>
addEventListener('keydown', function (e) { dump('FXKEY ' + e.key + '\n'); });
addEventListener('scroll', function () { dump('FXSCROLL ' + scrollY + '\n'); });
addEventListener('click', function (e) { dump('FXCLICK ' + e.clientX + ',' + e.clientY + '\n'); });
document.getElementById('i').addEventListener('input', function (e) { dump('FXINPUT ' + e.target.value + '\n'); });
dump('FXLOAD ' + document.getElementsByTagName('div').length + ' h=' + document.body.scrollHeight + '\n');
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
( while true; do echo "FX7 t=$(up) rss=$(rss) last=$(grep -a '^FX[A-Z]* ' /tmp/fx3.log | tail -n 1)"; sleep 10; done ) &
sleep ${FX7_WAIT:-420}
echo "FX7 all events:"
grep -a '^FX[A-Z]* ' /tmp/fx3.log | head -60
echo "FX7 widget log:"
grep -a -i "key\|focus\|enter\|leave\|seat" /tmp/fx3.log /tmp/e.log* | grep -av "FX[A-Z]* " | tail -${FX7_LOGTAIL:-40} | cut -c1-200
echo "FX7 logsize: $(wc -c < /tmp/fx3.log) fx3, $(wc -c /tmp/e.log* | tail -n 1)"
echo "FX7 fx3 tail:"
tail -n 15 /tmp/fx3.log | cut -c1-200
echo FX-END
