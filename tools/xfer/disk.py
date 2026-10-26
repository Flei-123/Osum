#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/xfer/disk.py -- reads files out of an OFS disk image on the host (the referee of the end-to-end runs).

    disk.py sum <image> <path>...          one line per path: `file <path> size=<n> sha=<hex>` or `missing <path>`
    disk.py png <image> <path> <reference.png>
                                           `png same` when the picture in <path> has the pixels of the reference
"""
import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "fsrobust"))
sys.path.insert(0, os.path.join(HERE, "..", "osum"))

import check  # noqa: E402
import mkfs   # noqa: E402


def read(img, path):
    ino = img.finde(path)
    if not ino:
        return None
    return img.lies(ino, 0, img.ig(ino, mkfs.I_SIZE))


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    img = check.Bild(argv[2])
    if not img.magic:
        print("not an OFS image")
        return 1
    if argv[1] == "sum":
        for p in argv[3:]:
            data = read(img, p)
            if data is None:
                print("missing %s" % p)
            else:
                print("file %s size=%d sha=%s" % (p, len(data), hashlib.sha1(data).hexdigest()))
        return 0
    if argv[1] == "png":
        from PIL import Image
        data = read(img, argv[3])
        if data is None:
            print("png missing")
            return 0
        try:
            got = Image.open(io.BytesIO(data)).convert("RGB")
            want = Image.open(argv[4]).convert("RGB")
        except Exception as exc:  # noqa: BLE001
            print("png unreadable %s" % exc)
            return 0
        print("png %s size=%dx%d" % ("same" if got.size == want.size and list(got.getdata()) == list(want.getdata()) else "different", got.size[0], got.size[1]))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
