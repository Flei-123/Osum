from registry import group
from report import info, verdict, warn

G = "audio"


@group(G, commands=["/bin/cat /proc/drivers", "/bin/cat /proc/pci"])
def audio(ctx):
    pci = [l for l in ctx.text("/bin/cat /proc/pci").splitlines() if " 0403 " in l]
    drivers = [l for l in ctx.text("/bin/cat /proc/drivers").splitlines() if l.startswith("hda ")]
    out = [verdict(G, "controller", bool(pci), pci[0] if pci else "no 0403 device")]
    state = drivers[0].split(" state=")[1].split()[0] if drivers and " state=" in drivers[0] else "absent"
    out.append(verdict(G, "driver", state in ("seen", "bound"), "hda state=%s" % state))
    out.append(info(G, "playback", "not testable through the read-only channel; needs the Boss at the device"))
    return out
