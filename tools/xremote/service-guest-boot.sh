/bin/settingsd check /etc/settings.schema
/bin/apprights load
/bin/orientbus serve 400000 &
sleep -m 300
/bin/settingsd serve 400000 &
sleep 1
/bin/xremoted nosession &
busybox sh /etc/svc.sh &
sleep 1000
