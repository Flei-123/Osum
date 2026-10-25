# SPDX-License-Identifier: GPL-2.0-only
import os

MAIN_SIZE = 72
ROW_SIZES = (44, 64)


def osym_ok(blob, size):
    return (len(blob) == 12 + size * size * 4 and blob[:4] == b"OSYM"
            and int.from_bytes(blob[4:8], "little") == size and int.from_bytes(blob[8:12], "little") == size)


def joined(bundle_dir):
    main = open(os.path.join(bundle_dir, "symbol.osym"), "rb").read()
    parts = [main]
    for size in ROW_SIZES:
        path = os.path.join(bundle_dir, "symbol%d.osym" % size)
        if not os.path.isfile(path):
            return main
        blob = open(path, "rb").read()
        if not osym_ok(blob, size):
            raise SystemExit("%s: not a %dx%d OSYM picture" % (path, size, size))
        parts.append(blob)
    if not osym_ok(main, MAIN_SIZE):
        return main
    return b"".join(parts)
