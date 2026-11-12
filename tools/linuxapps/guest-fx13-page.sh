echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 MOZ_ENABLE_WAYLAND=1 GDK_BACKEND=wayland MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1 FONTCONFIG_FILE=/etc/fonts/fonts.conf
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo 'user_pref("browser.shell.checkDefaultBrowser", false);' >> /tmp/p/user.js
echo 'user_pref("browser.dom.window.dump.enabled", true);' >> /tmp/p/user.js
cat > /tmp/page.html <<'HTML'
<html><body style="margin:0;background:#fff;font-family:sans-serif"><h1 style="font-size:64px;color:#06c">Firefox on OrientOS</h1><p style="font-size:40px">Running in a Wayland window on the Osum kernel.</p>
<script>dump('FXLOAD page\n');</script></body></html>
HTML
echo "FX13 launch"
/usr/lib/firefox/firefox --no-remote --profile /tmp/p file:///tmp/page.html > /tmp/fx3.log 2>&1 &
sleep ${FX13_WAIT:-420}
echo FX-END
