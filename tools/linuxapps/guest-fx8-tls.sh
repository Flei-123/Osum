echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
mkdir -p /tmp/p8
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p8/user.js
timeout 1300 /usr/bin/firefox --headless --screenshot /tmp/tls.png --window-size=1024,768 --profile /tmp/p8 https://10.0.2.2:__PORT__/ > /tmp/tls.log 2>&1
echo "FX8 rc=$? bytes=$(wc -c < /tmp/tls.png 2>/dev/null)"
tail -3 /tmp/tls.log
if [ -s /tmp/tls.png ]; then echo "FX8IMG-BEGIN"; base64 /tmp/tls.png; echo "FX8IMG-END"; fi
echo FX-END
