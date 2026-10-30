#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import shutil
import struct
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "tools", "appreg"))
import build  # noqa: E402

COLOR = (255, 0, 255, 255)


def old_symbol(size=16):
    return b"OSYM" + struct.pack("<II", size, size) + bytes(COLOR) * (size * size)


def main(argv):
    out, ids = argv[0], argv[1].split(",")
    shutil.copytree(os.path.join(ROOT, "assets", "apps"), out)
    rows = {r[0]: r for r in build.read_rows(os.path.join(ROOT, "tools/loader/apps.tab"), "|")}
    for app in ids:
        row = rows[app]
        pkg = os.path.join(out, app + ".osp")
        os.makedirs(os.path.join(pkg, "data"))
        with open(os.path.join(pkg, "INFO"), "w") as f:
            f.write("name=%s\ninfo=%s\nkeys=%s\nfassung=1\n" % (row[3], row[4], row[5]))
        with open(os.path.join(pkg, "start.txt"), "w") as f:
            f.write("/bin/%s\n" % (os.environ.get("PINSTART_BIN_" + app) or row[1]))
        with open(os.path.join(pkg, "data", "README"), "w") as f:
            f.write(app + "\n")
        with open(os.path.join(pkg, "symbol.osym"), "wb") as f:
            f.write(old_symbol())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
