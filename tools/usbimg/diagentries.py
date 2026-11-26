import sys

DROP_WORDS = ("vfs", "audio", "nic", "nsvc=0", "nwait=0", "dhcp", "jarvis")
VARIANTS = (
    ("no beam sync", ("nobeam",), ()),
    ("one CPU", ("nosmp",), ()),
    ("no network or audio", (), DROP_WORDS),
    ("no beam, one CPU, no network", ("nobeam", "nosmp"), DROP_WORDS),
)


def entry_body(lines, product):
    start = lines.index("/" + product) + 1
    end = start
    while end < len(lines) and lines[end].startswith(" "):
        end += 1
    return lines[start:end]


def variant_lines(body, name, add, drop):
    out = ["", "//%s" % name]
    for line in body:
        if not line.strip().startswith("cmdline:"):
            out.append(line)
            continue
        words = [w for w in line.split()[1:] if w != "safeauto"]
        words = [w for w in words if w not in drop and not w.startswith("nip=")] if drop else words
        out.append("    cmdline: " + " ".join(words + list(add)))
    return out


def main():
    path, product = sys.argv[1], sys.argv[2]
    lines = open(path).read().split("\n")
    body = entry_body(lines, product)
    while lines and lines[-1] == "":
        lines.pop()
    for label, add, drop in VARIANTS:
        lines += variant_lines(body, "%s (diagnose: %s)" % (product, label), add, drop)
    open(path, "w").write("\n".join(lines) + "\n")


main()
