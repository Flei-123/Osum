/bin/apprights load
/bin/orientbus serve 400000 &
sleep -m 300
/bin/settingsd serve 400000 &
sleep 1
wayd /tmp/wayland-0 2000000000 0 trace &
sleep 3
busybox sh /etc/fvgui.sh &
sleep 1000
