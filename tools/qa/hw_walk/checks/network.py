import re

from kv import as_int, merge_tokens, tokens
from registry import group
from report import fail, info, verdict, warn

G = "network"
WLAN = "/bin/cat /proc/wlan"


def gateway(ctx):
    for line in ctx.text("/bin/hwinv").splitlines():
        m = re.search(r"net: ip=(\S+) gw=(\S+)", line)
        if m:
            return m.group(2)
    return ""


@group(G, commands=[WLAN, "/bin/cat /proc/net/dev", "/bin/hwinv"], active_commands=["__ping__"])
def network(ctx):
    out = []
    wlan = ctx.text(WLAN)
    if wlan:
        kv = merge_tokens(wlan)
        out.append(verdict(G, "wlan firmware", kv.get("phase") == "ready" and kv.get("alive") == "yes" and kv.get("err") == "0",
                           "phase=%s alive=%s err=%s fw=%s" % (kv.get("phase"), kv.get("alive"), kv.get("err"), kv.get("fw_ver"))))
        nets = as_int(kv.get("nets"))
        out.append(verdict(G, "wlan scan", nets > 0, "%d networks, %s" % (nets, ", ".join(l.split()[1] for l in wlan.splitlines() if l.startswith("net "))[:80])))
        out.append(verdict(G, "wlan link", kv.get("uplink") == "1", "uplink=%s losses=%s" % (kv.get("uplink"), kv.get("losses")), otherwise="INFO"))
    else:
        out.append(fail(G, "/proc/wlan", "no answer"))
    dev = ctx.text("/bin/cat /proc/net/dev")
    ifaces = [l.split(":")[0].strip() for l in dev.splitlines() if ":" in l and "Inter" not in l and "face" not in l]
    out.append(verdict(G, "interfaces", bool(ifaces), ", ".join(ifaces) or "none"))
    gw = gateway(ctx)
    if ctx.active and gw:
        reply = ctx.bridge.run("/bin/ping " + gw, ctx.timeout)
        m = re.search(r"(\d+) transmitted, (\d+) received", reply.body)
        out.append(verdict(G, "ping gateway", bool(m) and m.group(2) != "0", "%s: %s" % (gw, m.group(0) if m else reply.body[:60])))
    else:
        out.append(info(G, "ping gateway", "skipped (passive run or no gateway)"))
    return out
