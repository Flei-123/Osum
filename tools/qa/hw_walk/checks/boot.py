from kv import as_int, colon_pairs, lines_with
from registry import group
from report import fail, info, ok, verdict, warn

WORDS = ("panic", "fault", "refused", "failed")
G = "boot"


@group(G, commands=["/bin/uname -a", "/bin/cat /proc/uptime", "/bin/cat /proc/watchdog", "/bin/ls /var/jarvis",
                    "/bin/cat /proc/version", "/bin/cat /var/jarvis/boot.log"] + ["/bin/grep %s /proc/klog" % w for w in WORDS])
def boot(ctx):
    out = []
    out.append(verdict(G, "uname", ctx.answered("/bin/uname -a"), ctx.text("/bin/uname -a").strip()[:80]))
    version = ctx.text("/bin/cat /proc/version").strip()
    out.append(verdict(G, "version", "build" in version, version[:100]))
    up = ctx.text("/bin/cat /proc/uptime").split()
    if up:
        out.append(info(G, "uptime", "%.1f h" % (float(up[0]) / 3600)))
    else:
        out.append(fail(G, "uptime", "no answer"))
    wd = {k: v for k, v in (l.split(None, 1) for l in ctx.text("/bin/cat /proc/watchdog").splitlines() if " " in l)}
    if wd:
        out.append(verdict(G, "watchdog armed", wd.get("state") == "armed", "state %s locked %s" % (wd.get("state"), wd.get("locked"))))
        reason = wd.get("last_boot", "?")
        out.append(verdict(G, "last boot reason", reason == "normal", "%s (detail %s)" % (reason, wd.get("last_boot_detail", "?")), otherwise="WARN"))
        out.append(verdict(G, "watchdog starved", as_int(wd.get("starved")) == 0, "starved=%s" % wd.get("starved"), otherwise="WARN"))
    else:
        out.append(fail(G, "watchdog", "no /proc/watchdog"))
    files = ctx.text("/bin/ls /var/jarvis").split()
    hangs = [f for f in files if f.startswith("panic-")]
    out.append(info(G, "hang reports", "%d files in /var/jarvis" % len(hangs)))
    boot_log = ctx.text("/bin/cat /var/jarvis/boot.log")
    out.append(verdict(G, "boot.log", len(boot_log) > 100, "%d bytes, %d lines" % (len(boot_log), boot_log.count("\n")), otherwise="WARN"))
    for line in boot_log.splitlines():
        if " E " in line[:30] or "FAIL" in line:
            out.append(warn(G, "boot.log error line", line.strip()[:140]))
            break
    for w in WORDS:
        reply = ctx.run("/bin/grep %s /proc/klog" % w)
        hits = [l for l in reply.body.splitlines() if l.startswith("[")] if reply.done else []
        if not reply.done:
            out.append(fail(G, "klog %s" % w, "grep did not answer"))
        else:
            out.append(verdict(G, "klog %s" % w, not hits, ("%d lines, first: %s" % (len(hits), hits[0][:110])) if hits else "none", otherwise="WARN"))
    return out
