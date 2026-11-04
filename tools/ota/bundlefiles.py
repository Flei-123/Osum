#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import filecmp
import os
import re
import shutil
import sys

ENTRY = re.compile(r"^/apps/([A-Za-z0-9._-]+\.osp)/(INFO|symbol|SYSTEM|data/README)=(.+)$")
ALWAYS = ("INFO",)


def select(listing, base_dir):
    chosen = {}
    for line in listing:
        m = ENTRY.match(line.strip())
        if not m:
            continue
        bundle, member, src = m.group(1), m.group(2), m.group(3)
        chosen.setdefault(bundle, {})[member] = src
    result = []
    for bundle, members in sorted(chosen.items()):
        base_sym = os.path.join(base_dir, bundle + ".symbol")
        fresh = not os.path.isfile(base_sym)
        changed = fresh or not filecmp.cmp(base_sym, members["symbol"], shallow=False)
        for member, src in sorted(members.items()):
            if member in ALWAYS or changed:
                result.append((bundle, member, src))
    return result


def main(argv):
    if len(argv) != 4:
        print("usage: bundlefiles.py <bundle.py listing> <baseline buendel dir> <extra dir>", file=sys.stderr)
        return 2
    listing = open(argv[1]).read().splitlines()
    picked = select(listing, argv[2])
    for bundle, member, src in picked:
        dest = os.path.join(argv[3], "apps", bundle, member)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(src, dest)
        print("bundlefiles: /apps/%s/%s" % (bundle, member))
    print("bundlefiles: %d files" % len(picked))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
