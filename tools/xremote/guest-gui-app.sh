echo "FVGUI start"
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 WINIT_UNIX_BACKEND=wayland XDG_SESSION_TYPE=wayland LIBGL_ALWAYS_SOFTWARE=1 EGL_PLATFORM=wayland FONTCONFIG_FILE=/etc/fonts/fonts.conf RUST_BACKTRACE=1 RUST_LOG=${FVGUI_LOG:-info} ${FVGUI_ENV:-}
busybox mkdir -p /root /tmp/xdg
[ -f /etc/fvsvc.sh ] && busybox sh /etc/fvsvc.sh
echo "FVGUI ldd:"
LD_TRACE_LOADED_OBJECTS=1 /opt/fv/freeviewer 2>&1 | busybox head -40
/opt/fv/freeviewer > /tmp/fvgui.log 2>&1 &
FVPID=$!
i=0
while [ $i -lt ${FVGUI_WAIT:-200} ]; do
    busybox sleep 5
    i=$((i + 5))
    busybox kill -0 $FVPID 2>/dev/null || { echo "FVGUI exited t=$i"; break; }
    busybox grep -aq "eframe\|egui\|FVGUI-READY" /tmp/fvgui.log && echo "FVGUI log-activity t=$i"
done
echo "FVGUI log:"
busybox head -80 /tmp/fvgui.log
echo "FVGUI tail:"
busybox tail -30 /tmp/fvgui.log
echo FX-END
