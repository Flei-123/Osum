from kv import as_int, merge_tokens
from registry import group
from report import fail, info, ok, verdict, warn

G = "acpi"
REQUIRED = ("DSDT", "FACP", "APIC", "MCFG")
DEVICES = (("battery", "acpi-battery"), ("lid", "acpi-lid"), ("embedded controller", "acpi-ec"), ("ac adapter", "acpi-ac"))


@group(G, commands=["/bin/cat /proc/acpi", "/bin/hwinv", "/bin/cat /proc/drivers"])
def acpi(ctx):
    text = ctx.text("/bin/cat /proc/acpi")
    if not text:
        return [fail(G, "/proc/acpi", "no answer")]
    out = []
    tables = []
    for line in text.splitlines():
        if line.startswith("tables:"):
            tables = line.split()[1:]
    missing = [t for t in REQUIRED if t not in tables]
    out.append(verdict(G, "tables", not missing, "%d tables%s" % (len(tables), (", missing " + ",".join(missing)) if missing else "")))
    hold = merge_tokens("\n".join(l for l in text.splitlines() if l.startswith("aml_hold:")))
    out.append(verdict(G, "aml namespace", "acpi_ns: yes" in text and hold.get("bad") == "0" and hold.get("e") == "0",
                       "nodes=%s bad=%s e=%s defer=%s" % (hold.get("nodes"), hold.get("bad"), hold.get("e"), hold.get("defer"))))
    drivers = ctx.text("/bin/cat /proc/drivers").splitlines()
    for label, name in DEVICES:
        hit = [l for l in drivers if l.startswith(name + " ") and "state=absent" not in l]
        out.append(verdict(G, label, bool(hit), hit[0][:70] if hit else name + " missing"))
    inv = ctx.text("/bin/hwinv")
    out.append(verdict(G, "hwinv acpi keys agree", "hwinv: acpi_battery=1" in inv, "hwinv run through the bridge reports acpi_battery=%s acpi_lid=%s acpi_ec=%s" % tuple(
        (inv.split("hwinv: %s=" % k)[1].split("\n")[0] if ("hwinv: %s=" % k) in inv else "?") for k in ("acpi_battery", "acpi_lid", "acpi_ec")), otherwise="WARN"))
    sci = merge_tokens("\n".join(l for l in text.splitlines() if l.startswith("scix ")))
    storms = as_int(sci.get("storms")) + as_int(sci.get("stray_gpe")) + as_int(sci.get("gpe_failed"))
    out.append(verdict(G, "sci health", storms == 0 and as_int(sci.get("masked")) == 0,
                       "irqs=%s storms=%s masked=%s stray_gpe=%s gpe_failed=%s" % (sci.get("irqs"), sci.get("storms"), sci.get("masked"), sci.get("stray_gpe"), sci.get("gpe_failed")), otherwise="WARN"))
    return out
