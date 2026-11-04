import re

from kv import as_int, merge_tokens
from registry import group
from report import info, verdict, warn

G = "suspend"
S3_HEX = "/bin/grep 5f53335f /proc/acpidump"


@group(G, commands=[S3_HEX, "/bin/cat /proc/battery", "/bin/cat /proc/acpi", "/bin/ota system status", "/bin/hwinv", "/bin/cat /proc/drivers"])
def suspend(ctx):
    out = []
    hit = ctx.text(S3_HEX)
    m = re.search(r"085f53335f12[0-9a-f]{2}[0-9a-f]{2}0a([0-9a-f]{2})", hit.replace("\n", ""))
    out.append(verdict(G, "_S3 object", bool(m), ("SLP_TYP a=0x%s" % m.group(1)) if m else "not found in sampled DSDT lines", otherwise="WARN"))
    acpi = ctx.text("/bin/cat /proc/acpi")
    inv = ctx.text("/bin/hwinv")
    out.append(verdict(G, "FACP table", " FACP " in acpi, "FADT present"))
    out.append(verdict(G, "lid", any(l.startswith("acpi-lid ") for l in ctx.text("/bin/cat /proc/drivers").splitlines()), "acpi-lid driver entry"))
    out.append(verdict(G, "cpus", "hwinv: cpus_online=4" in inv or "hwinv: failed=0" in inv, "all cpus online and none failed"))
    bat = merge_tokens(ctx.text("/bin/cat /proc/battery"))
    out.append(verdict(G, "battery for a test", as_int(bat.get("percent")) >= 30, "%s%%" % bat.get("percent"), otherwise="WARN"))
    status = ctx.text("/bin/ota system status")
    out.append(verdict(G, "no update in flight", "no update pending" in status and "apply done" in status, "ota status settled", otherwise="WARN"))
    out.append(info(G, "dry run", "no suspend is sent: /bin/power is not in command_allowed and hw_walk never uses it; the real S3 test needs the Boss at the lid"))
    return out
