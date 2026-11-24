#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import os
import re
import sys

MAGIC = b"OSDRV1\n"
MAX_ENTRY = 8 * 1024 * 1024
NAME_RE = re.compile(r"^(fw/)?[A-Za-z0-9][A-Za-z0-9._-]{0,30}$")


def pack(pkgdir, firmware):
    entries = []
    for name in sorted(os.listdir(pkgdir)):
        path = os.path.join(pkgdir, name)
        if os.path.isfile(path):
            entries.append((name, path))
    for name, path in firmware:
        entries.append(("fw/" + name, path))
    out = bytearray(MAGIC)
    for name, path in entries:
        if not NAME_RE.match(name):
            raise ValueError("bad entry name %s" % name)
        data = open(path, "rb").read()
        if len(data) > MAX_ENTRY:
            raise ValueError("entry too large: %s" % name)
        out += b"%s %d\n" % (name.encode(), len(data)) + data
    return bytes(out)


def unpack(blob):
    if not blob.startswith(MAGIC):
        raise ValueError("bad magic")
    pos = len(MAGIC)
    entries = []
    while pos < len(blob):
        end = blob.index(b"\n", pos)
        name, size = blob[pos:end].decode().rsplit(" ", 1)
        if not NAME_RE.match(name):
            raise ValueError("bad entry name %s" % name)
        pos = end + 1
        size = int(size)
        if pos + size > len(blob):
            raise ValueError("truncated entry %s" % name)
        entries.append((name, blob[pos:pos + size]))
        pos += size
    return entries


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pack")
    p.add_argument("pkgdir")
    p.add_argument("out")
    p.add_argument("--fw", action="append", default=[], help="NAME=PATH")
    u = sub.add_parser("list")
    u.add_argument("bundle")
    args = ap.parse_args()
    if args.cmd == "pack":
        firmware = [tuple(item.split("=", 1)) for item in args.fw]
        open(args.out, "wb").write(pack(args.pkgdir, firmware))
        return 0
    for name, data in unpack(open(args.bundle, "rb").read()):
        print(name, len(data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
