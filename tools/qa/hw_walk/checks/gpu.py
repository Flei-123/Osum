from kv import as_int, merge_tokens
from registry import group
from report import fail, info, verdict, warn

G = "gpu"
FLIP_OK = 7
BLIT_OK = 7


@group(G, commands=["/bin/cat /proc/intelgpu", "/bin/cat /proc/cmdline"])
def gpu(ctx):
    text = ctx.text("/bin/cat /proc/intelgpu")
    if "intelgpu: off" in text or not text.strip():
        return [warn(G, "intel-gpu driver", "boot word intelgpu not set, nothing to check")]
    kv = merge_tokens(text)
    out = [verdict(G, "device id", kv.get("device", "").lower().startswith("0x59"), "device=%s gen=%s" % (kv.get("device"), kv.get("gen")))]
    out.append(verdict(G, "EDID read over DP-AUX", kv.get("edid_status") == "ok", "status=%s %s %s" % (kv.get("edid_status"), kv.get("mfg"), kv.get("mode"))))
    out.append(verdict(G, "eDP pipe running", kv.get("edp_enabled") == "1" and kv.get("plane_enabled") == "1" and kv.get("panel_on") == "1",
                       "edp=%s plane=%s panel=%s" % (kv.get("edp_enabled"), kv.get("plane_enabled"), kv.get("panel_on"))))
    out.append(verdict(G, "refresh near 60 Hz", 59000 <= as_int(kv.get("refresh_mhz")) <= 61000, "%s mHz" % kv.get("refresh_mhz")))
    out.append(verdict(G, "no denied register writes", as_int(kv.get("denied")) == 0, "writes=%s denied=%s" % (kv.get("writes"), kv.get("denied"))))
    if "intelgpuflip" in ctx.text("/bin/cat /proc/cmdline"):
        out.append(verdict(G, "double buffer flip self-test", as_int(kv.get("flip_status")) == FLIP_OK and as_int(kv.get("flip_count")) > 0,
                           "flip_status=%s count=%s rollback=%s" % (kv.get("flip_status"), kv.get("flip_count"), kv.get("flip_rollback"))))
    if "intelgpublit" in ctx.text("/bin/cat /proc/cmdline"):
        out.append(verdict(G, "blitter submissions", as_int(kv.get("blit_status")) == BLIT_OK and as_int(kv.get("blit_hangs")) == 0,
                           "blit_status=%s verified=%s fills=%s copies=%s hangs=%s" % (kv.get("blit_status"), kv.get("blit_verified"), kv.get("blit_fills"), kv.get("blit_copies"), kv.get("blit_hangs"))))
    else:
        out.append(info(G, "flip/blit tests", "boot words intelgpuflip / intelgpublit not set"))
    return out
