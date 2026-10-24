import sys
routes = [
    ("/wlan", "F:/proc/wlan"),
    ("/drivers", "F:/proc/drivers"),
    ("/net", "F:/proc/net"),
    ("/pci", "F:/proc/pci"),
    ("/usb", "F:/proc/usb"),
    ("/lspci", "X:/bin/lspci"),
    ("/lspci/v", "X:/bin/lspci -v"),
    ("/dmesg", "X:/bin/log -n 400"),
    ("/klog", "F:/proc/klog"),
    ("/svclog", "F:/var/log/jarvisd.log"),
    ("/dbgsrvlog", "F:/var/log/dbgsrv.log"),
    ("/wlanctl/status", "X:/bin/wlanctl status"),
    ("/wlanctl/dump", "X:/bin/wlanctl dump>/tmp/wlan-dump.txt"),
    ("/version", "F:/proc/version"),
    ("/uptime", "F:/proc/uptime"),
]
names = "".join(r[0] + "\n" for r in routes)
targets = "".join(r[1] + "\n" for r in routes)
esc_names = names.replace("\n", "\\n")
esc_targets = targets.replace("\n", "\\n")
template = open(sys.argv[1]).read()
out = (template
       .replace("@NAMES_SIZE@", str(len(names) + 1))
       .replace("@NAMES@", esc_names)
       .replace("@NAMES_LEN@", str(len(names)))
       .replace("@TARGETS_SIZE@", str(len(targets) + 1))
       .replace("@TARGETS@", esc_targets)
       .replace("@TARGETS_LEN@", str(len(targets)))
       .replace("@COUNT@", str(len(routes))))
open(sys.argv[2], "w").write(out)
