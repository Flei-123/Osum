export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
mkdir -p /tmp/p /root
echo 'user_pref("gfx.webrender.software", true);' > /tmp/p/user.js
case "$1" in
  version) /usr/bin/firefox --version ;;
  shot) rm -f /tmp/x.png; /usr/bin/firefox --headless --screenshot /tmp/x.png --profile /tmp/p about:blank; echo "FX rc=$?"; ls -la /tmp/x.png ;;
  *) echo "usage: fxrun version|shot" ;;
esac
