from kv import as_int, merge_tokens, colon_pairs
from registry import group
from report import fail, info, ok, verdict, warn

G = "devices"
HWINV = "/bin/hwinv"
DRIVERS = "/bin/cat /proc/drivers"


def hwinv_map(text):
    out = {}
    for line in text.splitlines():
        if line.startswith("hwinv: ") and "=" in line:
            key, value = line[7:].split("=", 1)
            out.setdefault(key, value)
    return out


@group(G, commands=[HWINV, DRIVERS, "/bin/cat /proc/pci", "/bin/cat /proc/hwid"])
def devices(ctx):
    out = []
    inv = hwinv_map(ctx.text(HWINV))
    if not inv:
        return [fail(G, "hwinv", "no answer from /bin/hwinv")]
    out.append(verdict(G, "pci devices", as_int(inv.get("pci_devices")) >= 10, "pci_devices=%s" % inv.get("pci_devices")))
    out.append(verdict(G, "firmware", inv.get("firmware") in ("UEFI", "BIOS"), inv.get("firmware", "?")))
    out.append(verdict(G, "storage", inv.get("storage_verdict") == "ok", "%s verdict %s" % (inv.get("storage"), inv.get("storage_verdict"))))
    out.append(verdict(G, "cpus online", inv.get("cpus_online") == inv.get("cpus_madt") and inv.get("failed") == "0",
                       "online %s of %s, failed %s" % (inv.get("cpus_online"), inv.get("cpus_madt"), inv.get("failed"))))
    out.append(verdict(G, "gpu", inv.get("gpu", "none") != "none", inv.get("gpu", "none")))
    out.append(verdict(G, "framebuffer write", as_int(inv.get("fb_write_mbs")) >= 500, "%s MB/s cache %s" % (inv.get("fb_write_mbs"), inv.get("fb_cache_mode")), otherwise="WARN"))
    pointing = inv.get("pointing", "none")
    hid = as_int(inv.get("hid_devs"))
    out.append(verdict(G, "pointing driven", hid > 0, "pointing=%s hid_devs=%s i2c_ctrls=%s" % (pointing, hid, inv.get("i2c_ctrls")), otherwise="WARN"))
    out.append(verdict(G, "usb keyboard", as_int(inv.get("usb_kbd")) > 0, "usb_kbd=%s (internal PS/2 keyboard=%s)" % (inv.get("usb_kbd"), inv.get("acpi_ps2kbd")), otherwise="INFO"))
    out.append(verdict(G, "iommu", inv.get("iommu", "none") != "none", "iommu=%s" % inv.get("iommu"), otherwise="INFO"))
    out.append(verdict(G, "camera", as_int(inv.get("usb_camera")) > 0, "usb_camera=%s" % inv.get("usb_camera"), otherwise="INFO"))
    drivers = ctx.text(DRIVERS)
    unclaimed = [l for l in drivers.splitlines() if l.startswith("unclaimed ")]
    bound = [l.split()[0] for l in drivers.splitlines() if " state=bound" in l or " state=seen" in l]
    out.append(info(G, "drivers", "%d bound or seen, %d unclaimed PCI functions" % (len(bound), len(unclaimed))))
    hwid = colon_pairs(ctx.text("/bin/cat /proc/hwid"))
    out.append(verdict(G, "smbios", hwid.get("smbios_ok") == "1", "smbios_ok=%s product='%s'" % (hwid.get("smbios_ok"), hwid.get("system_product", "")), otherwise="INFO"))
    return out
