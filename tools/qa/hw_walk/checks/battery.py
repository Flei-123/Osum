from kv import as_int, merge_tokens
from registry import group
from report import fail, info, verdict, warn

G = "battery"


@group(G, commands=["/bin/cat /proc/battery", "/bin/cat /proc/thermal"])
def battery(ctx):
    kv = merge_tokens(ctx.text("/bin/cat /proc/battery"))
    if not kv:
        return [fail(G, "/proc/battery", "no answer")]
    out = [verdict(G, "present and valid", kv.get("present") == "1" and kv.get("valid") == "1", "present=%s valid=%s" % (kv.get("present"), kv.get("valid")))]
    full, rem, pct = as_int(kv.get("full")), as_int(kv.get("rem")), as_int(kv.get("percent"))
    calc = rem * 100 // full if full else -1
    out.append(verdict(G, "percent consistent", full > 0 and abs(calc - pct) <= 3, "reported %d%%, rem/full %d/%d = %d%%" % (pct, rem, full, calc)))
    out.append(info(G, "charge", "%d%% state=%s" % (pct, kv.get("state"))))
    hot = []
    for line in ctx.text("/bin/cat /proc/thermal").splitlines():
        if line.startswith("zone ") and " present=1" in line:
            t = [x for x in line.split() if x.startswith("temp_c=")]
            try:
                if t and float(t[0][7:]) > 85:
                    hot.append(line.split()[1])
            except ValueError:
                pass
    out.append(verdict(G, "thermal", not hot, "hot zones: %s" % ", ".join(hot) if hot else "all zones <= 85 C"))
    return out
