#!/usr/bin/env python3
import sys


def strip_boot(path):
    for prefix in ("boot():", "boot:///"):
        if path.startswith(prefix):
            path = path[len(prefix):]
    if not path.startswith("/"):
        path = "/" + path
    return path


def parse_limine(text):
    timeout, default, entries, cur = 5, 1, [], None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("/"):
            title = line.lstrip("/").strip()
            cur = {"title": title, "kernel": None, "modules": [], "cmdline": "", "proto": None}
            entries.append(cur)
            continue
        if ":" not in line:
            continue
        key, value = [x.strip() for x in line.split(":", 1)]
        if cur is None:
            if key == "timeout":
                timeout = int(value)
            elif key == "default_entry":
                default = int(value)
            continue
        if key in ("path", "kernel_path"):
            cur["kernel"] = strip_boot(value)
        elif key == "module_path":
            cur["modules"].append(strip_boot(value))
        elif key in ("cmdline", "kernel_cmdline"):
            cur["cmdline"] = value
        elif key == "protocol":
            cur["proto"] = value
    return timeout, default, [e for e in entries if e["kernel"] and e["proto"] == "multiboot1"]


def render(timeout, default, entries, resolution=None):
    out = ["timeout %d" % timeout, "default %d" % (default if 1 <= default <= len(entries) else 1)]
    if resolution:
        out.append("resolution %s" % resolution)
    for e in entries:
        out.append("")
        out.append("entry %s" % e["title"])
        out.append("kernel %s" % e["kernel"])
        for m in e["modules"]:
            out.append("module %s" % m)
        if e["cmdline"]:
            out.append("cmdline %s" % e["cmdline"])
    return "\n".join(out) + "\n"


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: mkcfg.py <limine.conf> <osboot.cfg> [--timeout N] [--resolution WxH]\n")
        return 2
    timeout, default, entries = parse_limine(open(argv[1]).read())
    resolution = None
    rest = argv[3:]
    while rest:
        flag = rest.pop(0)
        if flag == "--timeout":
            timeout = int(rest.pop(0))
        elif flag == "--resolution":
            resolution = rest.pop(0)
    if not entries:
        sys.stderr.write("mkcfg: no multiboot1 entry in %s\n" % argv[1])
        return 1
    if len(entries) > 16:
        entries = entries[:16]
    open(argv[2], "w").write(render(timeout, default, entries, resolution))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
