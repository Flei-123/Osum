from kv import as_int, tokens
from registry import group
from report import fail, info, verdict, warn

G = "usb"


@group(G, commands=["/bin/cat /proc/usbsum"])
def usb(ctx):
    text = ctx.text("/bin/cat /proc/usbsum")
    if not text:
        return [fail(G, "/proc/usbsum", "no answer")]
    out = []
    head = tokens(text.splitlines()[0])
    hosts = [tokens(l) for l in text.splitlines() if l.startswith("h") and " init=" in l and l[1].isdigit()]
    up = [h for h in hosts if h.get("init") == "ok"]
    out.append(verdict(G, "host controller", bool(up), "%d of %s controllers init ok, selected %s" % (len(up), head.get("hc"), head.get("sel")), otherwise="FAIL" if hosts else "WARN"))
    for h in hosts:
        if h.get("init") != "ok":
            out.append(warn(G, "controller init", "init=%s ports=%s" % (h.get("init"), h.get("ports"))))
    for h in up:
        out.append(verdict(G, "transfer errors", as_int(h.get("err")) <= 5, "cmd=%s evt=%s err=%s rf=%s" % (h.get("cmd"), h.get("evt"), h.get("err"), h.get("rf")), otherwise="WARN"))
    devs = [l for l in text.splitlines() if l.startswith("dev ")]
    out.append(info(G, "devices", "%d enumerated" % len(devs)))
    return out
