echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
export MOZ_LOG="${FX_MOZ_LOG:-timestamp,sync,nsHostResolver:4,nsSocketTransport:4,nsHttp:5,pipnss:4}"
mkdir -p /tmp/p10
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p10/user.js
: > /tmp/e.log
tail -f /tmp/e.log &
echo "FX10 begin firefox ${FX_URL:-https://example.com}"
timeout ${FX_TMO:-600} /usr/bin/firefox --headless --screenshot /tmp/e.png --window-size=1024,768 --profile /tmp/p10 ${FX_URL:-https://example.com} >> /tmp/e.log 2>&1
echo "FX10 rc=$? bytes=$(wc -c < /tmp/e.png 2>/dev/null)"
sleep 2
echo FX-END
