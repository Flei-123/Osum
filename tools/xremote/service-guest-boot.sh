/bin/settingsd check /etc/settings.schema
/bin/apprights load
/bin/xremoted nosession &
busybox sh /etc/svc.sh &
sleep 1000
