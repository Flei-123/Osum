echo "ACGUI start $AC_APP"
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 WINIT_UNIX_BACKEND=wayland XDG_SESSION_TYPE=wayland
export WORDCRAFT_WAYLAND=1 GRIDCRAFT_WAYLAND=1 DECKCRAFT_WAYLAND=1 ARTCRAFT_WAYLAND=1
export WGPU_BACKEND=gl LIBGL_ALWAYS_SOFTWARE=1 EGL_PLATFORM=wayland MESA_LOADER_DRIVER_OVERRIDE=swrast
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri
export RUST_BACKTRACE=1 RUST_LOG=${AC_LOG:-info,wgpu_hal=debug}
busybox mkdir -p /root /tmp/xdg
echo "ACGUI ldd:"
LD_TRACE_LOADED_OBJECTS=1 /opt/ac/$AC_APP 2>&1 | busybox head -20
/opt/ac/$AC_APP > /tmp/acgui.log 2>&1 &
PID=$!
i=0
while [ $i -lt ${AC_WAIT:-300} ]; do
    busybox sleep 5
    i=$((i + 5))
    busybox kill -0 $PID 2>/dev/null || { echo "ACGUI exited t=$i"; break; }
done
echo "ACGUI log:"
busybox head -60 /tmp/acgui.log
echo "ACGUI tail:"
busybox tail -30 /tmp/acgui.log
echo FX-END
