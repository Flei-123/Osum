from registry import group
from report import fail, info, verdict

G = "standby"


@group(G, commands=["/bin/cat /proc/s3"])
def standby(ctx):
    text = ctx.text("/bin/cat /proc/s3")
    kv = {}
    for line in text.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            kv[parts[0]] = parts[1].strip()
    if not kv:
        return [fail(G, "/proc/s3", "no answer")]
    out = [verdict(G, "FACS found", kv.get("facs", "0x00000000") != "0x00000000", "facs=%s why=%s (%s)" % (kv.get("facs"), kv.get("why"), kv.get("why_text")))]
    out.append(verdict(G, "S3 sleep type known", kv.get("why") == "0", "why=%s slp_typ_a=%s" % (kv.get("why"), kv.get("slp_typ_a"))))
    if int(kv.get("cycles", "0") or 0):
        out.append(verdict(G, "last cycle", kv.get("result") == "1", "cycles=%s result=%s slept_s=%s" % (kv.get("cycles"), kv.get("result"), kv.get("slept_s"))))
    else:
        out.append(info(G, "last cycle", "no standby since boot"))
    return out
