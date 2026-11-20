import re
import sys

LAST_NR = 459
UNASSIGNED = range(335, 424)
SKIPPED = {15: "rt_sigreturn", 56: "clone", 58: "vfork", 60: "exit", 169: "reboot", 231: "exit_group", 435: "clone3"}


def parse_names(path):
    text = re.sub(r"\n\t", " ", open(path).read())
    names = {}
    for line in text.split("\n"):
        head = re.match(r"^(\d+)\s+(\S+)\s+(STD|NOPROTO|UNIMPL|OBSOL|NODEF|NOSTD)\b(.*)$", line)
        if not head:
            continue
        nr, kind, rest = int(head.group(1)), head.group(3), head.group(4)
        if kind in ("UNIMPL", "OBSOL"):
            found = re.match(r"\s*(\w+)", rest)
        else:
            found = re.search(r"\{[^}]*?\b(\w+)\(", rest)
        if found:
            names[nr] = found.group(1).removeprefix("linux_").removeprefix("sys_")
    return names


def main():
    names = parse_names(sys.argv[1])
    out = ["static const struct sysent {", "    long nr;", "    const char *name;", "    int skip;", "} sysents[] = {"]
    for nr in range(LAST_NR + 1):
        name = names.get(nr, "nr_%d" % nr)
        out.append('    {%d, "%s", %d},' % (nr, name, 1 if nr in SKIPPED or nr in UNASSIGNED else 0))
    out.append("};")
    open(sys.argv[2], "w").write("\n".join(out) + "\n")


main()
