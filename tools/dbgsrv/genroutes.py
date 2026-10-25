import os
import re
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
    ("/wlanpoll", "F:/proc/wlanpoll"),
    ("/wlanirq", "F:/proc/wlanirq"),
    ("/usbnet", "F:/proc/usbnet"),
    ("/usbsum", "F:/proc/usbsum"),
    ("/time", "F:/proc/clock"),
    ("/wlanctl/knobs", "X:/bin/wlanctl reload list"),
]

here = os.path.dirname(os.path.abspath(__file__))
knob_src = os.path.join(here, "..", "..", "kernel", "net", "wlan_knobs.fi")
knob_text = open(knob_src).read()
match = re.search(r'static mut NAMES: \[u8; \d+\] = "([^"]*)\\0"', knob_text)
knobs = [k for k in match.group(1).split("\\n") if k]

reload_path = "/wlanctl/reload"
actions = [(reload_path + "?param=none", "X:/bin/wlanctl reload")]
for knob in knobs:
    for value in ("on", "off"):
        actions.append((reload_path + "?param=" + knob + "&value=" + value, "X:/bin/wlanctl reload " + knob + " " + value))
bases = [reload_path]


def table(items):
    text = "".join(i + "\n" for i in items)
    return text, text.replace("\n", "\\n")


names, esc_names = table([r[0] for r in routes])
targets, esc_targets = table([r[1] for r in routes])
anames, esc_anames = table([a[0] for a in actions])
atargets, esc_atargets = table([a[1] for a in actions])
abases, esc_abases = table(bases)
template = open(sys.argv[1]).read()
out = (template
       .replace("@NAMES_SIZE@", str(len(names) + 1))
       .replace("@NAMES@", esc_names)
       .replace("@NAMES_LEN@", str(len(names)))
       .replace("@TARGETS_SIZE@", str(len(targets) + 1))
       .replace("@TARGETS@", esc_targets)
       .replace("@TARGETS_LEN@", str(len(targets)))
       .replace("@COUNT@", str(len(routes)))
       .replace("@ANAMES_SIZE@", str(len(anames) + 1))
       .replace("@ANAMES@", esc_anames)
       .replace("@ANAMES_LEN@", str(len(anames)))
       .replace("@ACOUNT@", str(len(actions)))
       .replace("@ATARGETS_SIZE@", str(len(atargets) + 1))
       .replace("@ATARGETS@", esc_atargets)
       .replace("@ATARGETS_LEN@", str(len(atargets)))
       .replace("@ABASES_SIZE@", str(len(abases) + 1))
       .replace("@ABASES@", esc_abases)
       .replace("@ABASES_LEN@", str(len(abases)))
       .replace("@ABCOUNT@", str(len(bases))))
open(sys.argv[2], "w").write(out)
