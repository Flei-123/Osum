echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
export MOZ_LOG="${FXLOG:-timestamp,sync,nsDocShell:4,DocumentChannel:4,BrowsingContext:4,nsHttp:3,pipnss:5,CertVerifier:5,IPC:3,nsSocketTransport:4,PageLoad:4}"
export MOZ_LOG_FILE=/tmp/e.log
mkdir -p /tmp/p10
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p10/user.js
up() { read u _ < /proc/uptime; echo $u; }
echo "FX10 begin ${FX_URL:-https://example.com} t=$(up)"
timeout ${FX_TMO:-600} /usr/bin/firefox --headless --screenshot /tmp/e.png --window-size=1024,768 --profile /tmp/p10 ${FX_URL:-https://example.com} > /tmp/e.out 2>&1 &
FP=$!
n=0
while kill -0 $FP 2>/dev/null; do
  sleep 20
  n=$((n+1))
  echo "FX10 tick t=$(up) png=$(wc -c < /tmp/e.png 2>/dev/null) logbytes=$(wc -c < /tmp/e.log 2>/dev/null) procs=$(pidof firefox | wc -w)"
done
wait $FP
echo "FX10 rc=$? bytes=$(wc -c < /tmp/e.png 2>/dev/null) t=$(up)"
ls -la /tmp | head -30
echo "FX10 OUT"; tail -n 20 /tmp/e.out | cut -c1-200
for f in /tmp/e.log*; do echo "FX10LOG-BEGIN $f"; gzip -9 -c $f | base64; echo "FX10LOG-END $f"; done
echo FX-END
