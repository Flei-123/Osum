busybox mkdir /tmp/guiapps.lock || exit 0
echo "GUIAPP start"
export HOME=/root XDG_RUNTIME_DIR=/tmp WAYLAND_DISPLAY=/tmp/wayland-0 FONTCONFIG_FILE=/etc/fonts/fonts.conf GSETTINGS_BACKEND=memory NO_AT_BRIDGE=1 LIBGL_ALWAYS_SOFTWARE=1 XDG_DATA_DIRS=/usr/share
busybox mkdir -p /root /tmp/xdg
IMG=$(busybox find /usr/share/icons/Adwaita -name '*.png' | busybox head -1)
echo "GUIAPP base"
sleep 5
echo "GUIAPP basedone"
while IFS='|' read -r name toolkit category envs cmd; do
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    cmd=$(echo "$cmd" | busybox sed "s#@IMG@#$IMG#;s#@PDF@#/usr/share/guiapps/sample.pdf#")
    echo "GUIAPP begin $name"
    busybox env $envs $cmd > /tmp/$name.log 2>&1 &
    PID=$!
    i=0
    while [ $i -lt ${GUIAPP_WAIT:-40} ]; do
        sleep 2
        i=$((i + 2))
        busybox kill -0 $PID 2>/dev/null || break
        busybox cat /proc/$PID/maps > /tmp/$name.maps 2>/dev/null
    done
    echo "GUIAPP shot $name"
    sleep 4
    echo "GUIAPP keys $name"
    sleep 8
    echo "GUIAPP shot2 $name"
    sleep 4
    if busybox kill -0 $PID 2>/dev/null; then echo "GUIAPP alive $name"; else wait $PID; rc=$?; echo "GUIAPP exited $name rc=$rc"; if [ $rc -ge 128 ]; then echo "GUIAPP maps $name: $(busybox tr '\n' '|' < /tmp/$name.maps | busybox head -c 6000)"; fi; fi
    busybox kill $PID 2>/dev/null
    sleep 2
    busybox kill -9 $PID 2>/dev/null
    echo "GUIAPP log $name: $(busybox head -c 1200 /tmp/$name.log | busybox tr '\n' ' ')"
    echo "GUIAPP end $name"
done < /etc/guiapps.conf
echo FX-END
