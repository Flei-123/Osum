from registry import group
from report import fail, info, ok, verdict

G = "access"
DENIED_COMMANDS = ["/bin/rm /tmp/hw_walk_probe", "/bin/sh", "/bin/su", "/bin/login", "/bin/glogin", "/bin/passwd", "/bin/elevate",
                   "/bin/mount", "/bin/busybox", "ls /"]
SECRET_PATHS = ["/etc/jarvis/device.key", "/etc/shadow", "/etc/passwd"]
FORBIDDEN_IN_PERMISSIONS = ["/bin/sh", "/bin/su", "/bin/login", "/bin/glogin", "/bin/passwd", "/bin/elevate", "/bin/lock", "/bin/osh", "/bin/busybox"]


def reply_refused(reply):
    return reply.http == 200 and reply.job_status == "failed"


@group(G, commands=["/bin/cat /etc/jarvis/permissions.conf"])
def access(ctx):
    out = []
    b = ctx.bridge
    for label, kwargs in (("no admin key", dict(key=None)), ("wrong admin key", dict(key="x" * 32))):
        for method, path, body in (("GET", "/bridge/devices", None), ("POST", "/bridge/job", dict(device=b.device, kind="run", target="/bin/ls /")),
                                   ("GET", "/bridge/fetch?device=%s&id=1" % b.device, None)):
            code, _, _ = b.request(method, path, body, **kwargs)
            out.append(verdict(G, "%s -> %s %s" % (label, method, path.split("?")[0]), code == 403, "HTTP %s" % code))
    perms = ctx.text("/bin/cat /etc/jarvis/permissions.conf")
    allowed = {l.split("=", 1)[1].strip() for l in perms.splitlines() if l.startswith("command_allowed")}
    bad = [p for p in FORBIDDEN_IN_PERMISSIONS if p in allowed]
    out.append(verdict(G, "no login or shell program allowed", not bad, ", ".join(bad) or "none of %d forbidden programs listed" % len(FORBIDDEN_IN_PERMISSIONS)))
    out.append(verdict(G, "input disabled", any(l.replace(" ", "") == "input=no" for l in perms.splitlines()), "input = no"))
    if not ctx.active:
        return out + [info(G, "device refusals", "skipped (passive run)")]
    for cmd in DENIED_COMMANDS:
        r = b.run(cmd, ctx.timeout)
        out.append(verdict(G, "refused: " + cmd, reply_refused(r), "%s %s" % (r.job_status, r.text[:70].replace("\n", " "))))
    for path in SECRET_PATHS:
        r = b.read(path, ctx.timeout)
        out.append(verdict(G, "read refused: " + path, reply_refused(r), "%s %s" % (r.job_status, r.text[:60].replace("\n", " "))))
        r = b.run("/bin/cat " + path, ctx.timeout)
        leaked = r.done and r.exit_code == 0 and len(r.body.strip()) > 0
        out.append(verdict(G, "cat refused: " + path, not leaked, "command channel returned %d bytes" % len(r.body) if leaked else "refused", otherwise="FAIL"))
    r = b.job("write", "/etc/hw_walk_probe", "x", ctx.timeout)
    out.append(verdict(G, "write refused outside /tmp", reply_refused(r), r.text[:70]))
    r = b.job("input", "scan 28 156", "", ctx.timeout)
    out.append(verdict(G, "input refused", reply_refused(r), r.text[:70]))
    return out
