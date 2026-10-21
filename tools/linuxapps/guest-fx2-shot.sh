echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
echo "FX2 begin firefox --headless --screenshot"
timeout 500 /usr/bin/firefox --headless --screenshot /tmp/x.png --profile /tmp/p about:blank
echo "FX2 rc=$?"
ls -la /tmp/x.png
echo FX-END
