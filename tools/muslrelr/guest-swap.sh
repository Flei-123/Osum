echo "FX start"
export HOME=/root XDG_RUNTIME_DIR=/tmp MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_SOCKET_PROCESS_SANDBOX=1 MOZ_DISABLE_RDD_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 MOZ_CRASHREPORTER_DISABLE=1
cp /lib/swap-musl.so /lib/new.so
mv /lib/new.so /lib/ld-musl-x86_64.so.1
echo "MUSLRELR swapped"
/lib/busybox echo MUSLRELR busybox ok
/usr/lib/firefox/firefox --version
echo "MUSLRELR rc=$?"
echo FX-END
