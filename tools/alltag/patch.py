#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    patch.py <file> <alt-file> <renewed-file>
"""
import sys


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    path, alt_p, new_p = sys.argv[1:4]
    text = open(path, "rb").read().decode("utf-8", "surrogateescape")
    alt = open(alt_p, "rb").read().decode("utf-8", "surrogateescape")
    new = open(new_p, "rb").read().decode("utf-8", "surrogateescape")
    n = text.count(alt)
    if n != 1:
        print("patch.py: %s: the old piece occurs %d times, not once" % (path, n))
        return 1
    text = text.replace(alt, new, 1)
    open(path, "wb").write(text.encode("utf-8", "surrogateescape"))
    print("patch.py: %s: ersetzt (%d -> %d Zeichen)" % (path, len(alt), len(new)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
