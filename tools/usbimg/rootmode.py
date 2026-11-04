import re
import sys


def strip_module(path):
    lines = open(path).read().split("\n")
    out = []
    entry = 0
    for line in lines:
        if line.startswith("/"):
            entry += 1
        if entry == 1:
            if line.strip().startswith("module_path:"):
                continue
            if line.strip().startswith("cmdline:"):
                line = re.sub(r"(cmdline:\s*)modfs\s+", r"\1", line)
                line = re.sub(r"\s+modfs(\s|$)", r"\1", line)
        out.append(line)
    open(path, "w").write("\n".join(out))


if __name__ == "__main__":
    strip_module(sys.argv[1])
