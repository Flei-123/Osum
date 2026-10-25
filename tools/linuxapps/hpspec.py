#!/usr/bin/env python3
import sys

KEEP_PREFIXES = ("/usr/", "/var/cache/fontconfig", "/etc/fonts", "/etc/gtk-3.0", "/etc/xdg")
KEEP_EXACT = {"/lib/libc.musl-x86_64.so.1->ld-musl-x86_64.so.1"}
SKIP_DIRS = {"/usr/", "/usr/share/"}


def spec_path(line):
    for sep in ("=", "->", "@"):
        idx = line.find(sep)
        if idx > 0:
            return line[:idx]
    return line


def main(argv):
    spec_in, spec_out, launcher = argv[1], argv[2], argv[3]
    out = []
    for raw in open(spec_in, encoding="utf-8").read().splitlines():
        line = raw.strip()
        if not line:
            continue
        path = spec_path(line)
        if line in KEEP_EXACT:
            out.append(line)
        elif path in SKIP_DIRS:
            continue
        elif path.startswith(KEEP_PREFIXES) or path in ("/etc/fonts/", "/etc/gtk-3.0/", "/etc/xdg/", "/var/cache/", "/var/cache/fontconfig/"):
            out.append(line)
    out.append("/bin/fxrun=%s@755" % launcher)
    open(spec_out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("hpspec: %d entries" % len(out))


if __name__ == "__main__":
    main(sys.argv)
