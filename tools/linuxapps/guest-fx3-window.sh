echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 MOZ_ENABLE_WAYLAND=1 GDK_BACKEND=wayland MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 FONTCONFIG_FILE=/etc/fonts/fonts.conf
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo 'user_pref("browser.shell.checkDefaultBrowser", false);' >> /tmp/p/user.js
/bin/wayd /tmp/wayland-0 2000000000 &
sleep 3
echo "FX3 begin firefox window"
/usr/bin/firefox --no-remote --profile /tmp/p about:blank > /tmp/fx3.log 2>&1 &
FXP=$!
sleep ${FX3_WAIT:-240}
echo "FX3 ps: $(ps 2>&1 | head -30)"
echo "FX3 log:"
head -60 /tmp/fx3.log
ls -la /tmp/wayland-0 /var/crash 2>&1 | head
echo FX-END
