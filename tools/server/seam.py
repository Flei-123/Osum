#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def exports(path):
    text = open(path, encoding="utf8").read()
    block = re.search(r"^export\s*\{(.*?)\}", text, re.S | re.M).group(1)
    block = re.sub(r"//[^\n]*", "", block)
    return set(n.strip() for n in block.replace("\n", ",").split(",") if n.strip())


def main():
    full, stub = exports(sys.argv[1]), exports(sys.argv[2])
    only_full = sorted(full - stub)
    only_stub = sorted(stub - full)
    print("seam exports: full=%d stub=%d" % (len(full), len(stub)))
    if only_full or only_stub:
        print("only in full: %s" % " ".join(only_full))
        print("only in stub: %s" % " ".join(only_stub))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
