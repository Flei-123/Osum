echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_CRASHREPORTER_DISABLE=1 MOZ_SANDBOX_LOGGING=1 MOZ_LOG=SandboxBroker:5,Sandbox:5 MOZ_LOG_FILE=/tmp/sb.log
mkdir -p /tmp/p
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
echo 'user_pref("security.sandbox.content.level", 4);' >> /tmp/p/user.js
echo "FX15 begin firefox --headless --screenshot with content sandbox"
timeout 500 /usr/bin/firefox --headless --screenshot /tmp/x.png --profile /tmp/p 'data:text/html,<h1>osum</h1>'
echo "FX15 rc=$?"
ls -la /tmp/x.png
if [ -s /tmp/x.png ]; then echo "FX15 png ok"; fi
echo "FX15 sandbox log:"
head -c 3000 /tmp/sb.log
echo FX-END
