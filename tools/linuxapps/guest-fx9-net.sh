echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
echo "FX9 resolv: $(cat /etc/resolv.conf | tr '\n' ' ')"
echo "FX9 nslookup: $(timeout 20 nslookup example.com 2>&1 | tr '\n' ' ' | head -c 300)"
echo "FX9 wget-http: $(timeout 40 wget -q -O - http://example.com/ 2>&1 | head -c 60 | tr -d '\n')"
echo "FX9 wget-https: $(timeout 60 wget -q -O - https://example.com/ 2>&1 | head -c 60 | tr -d '\n')"
mkdir -p /tmp/p9
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p9/user.js
echo "FX9 begin firefox"
timeout ${FX_TMO:-600} /usr/bin/firefox --headless --screenshot /tmp/e.png --window-size=1024,768 --profile /tmp/p9 https://example.com > /tmp/e.log 2>&1
echo "FX9 rc=$? bytes=$(wc -c < /tmp/e.png 2>/dev/null)"
tail -5 /tmp/e.log
echo FX-END
