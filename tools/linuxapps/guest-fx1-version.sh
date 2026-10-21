echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
echo "FX ls: $(ls -la /usr/lib/firefox/libxul.so)"
echo "FX1 begin firefox --version"
timeout 500 /usr/bin/firefox --version
echo "FX1 rc=$?"
echo FX-END
