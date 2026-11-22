#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import shutil
import sys

ENTRY = re.compile(r"^/apps/([A-Za-z0-9._-]+\.osp)/(INFO|SYSTEM|data/README)=(.+)$")


def select(listing):
    result = []
    for line in listing:
        m = ENTRY.match(line.strip())
        if m:
            result.append((m.group(1), m.group(2), m.group(3)))
    return sorted(result)


def main(argv):
    if len(argv) != 3:
        print("usage: bundlefiles.py <bundle.py listing> <extra dir>", file=sys.stderr)
        return 2
    listing = open(argv[1]).read().splitlines()
    picked = select(listing)
    for bundle, member, src in picked:
        dest = os.path.join(argv[2], "apps", bundle, member)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(src, dest)
        print("bundlefiles: /apps/%s/%s" % (bundle, member))
    print("bundlefiles: %d files" % len(picked))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
