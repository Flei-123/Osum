#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "k15"))
import symjoin  # noqa: E402


def read_rows(path, sep):
    for line in open(path, encoding="utf-8").read().splitlines():
        if line.strip() and not line.startswith("#"):
            yield line.split(sep)


def icon_dir(root, app, aliases):
    for cand in (aliases.get(app), "assets/pkgicons/" + app, "assets/apps/%s.osp" % app):
        if cand and os.path.isfile(os.path.join(root, cand, "symbol.osym")):
            return os.path.join(root, cand)
    return None


def entries(root):
    aliases = dict(read_rows(os.path.join(root, "tools/appreg/alias.tsv"), "\t"))
    for row in read_rows(os.path.join(root, "tools/loader/apps.tab"), "|"):
        yield row[0], row[6], icon_dir(root, row[0], aliases)


def main(argv):
    root, out = argv[0], argv[1]
    bad = 0
    for app, kind, d in entries(root):
        if d is None:
            print("no icon source for %s" % app)
            bad += 1
            continue
        target = os.path.join(out, "usr/share/appreg", app)
        os.makedirs(target, exist_ok=True)
        with open(os.path.join(target, "symbol"), "wb") as f:
            f.write(symjoin.joined(d))
        if kind == "konsole":
            with open(os.path.join(target, "console"), "w") as f:
                f.write("1\n")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
