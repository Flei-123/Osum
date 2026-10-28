echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 MOZ_ENABLE_WAYLAND=1 WAYLAND_DEBUG=1 GDK_BACKEND=wayland MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 ${FX3_ENV:-} FONTCONFIG_FILE=/etc/fonts/fonts.conf
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo 'user_pref("browser.shell.checkDefaultBrowser", false);' >> /tmp/p/user.js
echo "FX3 begin firefox window"
/usr/lib/firefox/firefox --no-remote --profile /tmp/p about:blank > /tmp/fx3.log 2>&1 &
sleep ${FX3_WAIT:-240}
echo "FX3 ps: $(busybox ps 2>&1 | busybox grep -v '{[^}]*}.*firefox' | head -40)"
echo "FX3 log:"
busybox head -${FX3_HEAD:-60} /tmp/fx3.log
echo "FX3 first:"
busybox grep -a "wl_display#1.get_registry" /tmp/fx3.log | busybox head -1
echo "FX3 tail:"
busybox tail -${FX3_TAIL:-80} /tmp/fx3.log
busybox ls -la /tmp/wayland-0 /var/crash 2>&1 | busybox head
echo FX-END
