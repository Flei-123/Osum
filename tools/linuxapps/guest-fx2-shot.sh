echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo "FX2 begin firefox --headless --screenshot"
timeout 500 /usr/bin/firefox --headless --screenshot /tmp/x.png --profile /tmp/p 'data:text/html,<h1>osum</h1>'
echo "FX2 rc=$?"
ls -la /tmp/x.png
if [ -s /tmp/x.png ]; then echo "FX2 png ok"; fi
echo FX-END
