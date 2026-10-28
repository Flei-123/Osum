echo FXPACK begin
tar -xf /firefox.tar
echo FXPACK extracted rc=$?
wayd /tmp/wayland-0 2000000000 0 trace &
sleep 3
busybox sh /etc/fx3.sh &
sleep 1000
