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
    apps_dir = os.environ.get("APPS_DIR")
    for cand in (aliases.get(app), "assets/pkgicons/" + app, "assets/apps/%s.osp" % app):
        if cand and apps_dir and cand.startswith("assets/apps/"):
            cand = os.path.join(os.path.abspath(apps_dir), os.path.basename(cand))
        base = cand if cand and os.path.isabs(cand) else os.path.join(root, cand or "")
        if cand and os.path.isfile(os.path.join(base, "symbol.osym")):
            return base
    return None


def alias_target(root, app):
    aliases = dict(read_rows(os.path.join(root, "tools/appreg/alias.tsv"), "\t"))
    path = aliases.get(app)
    if not path or not path.startswith("assets/apps/") or not path.endswith(".osp"):
        return None
    name = os.path.basename(path)[:-4]
    return name if name != app else None


def bundle_title(path):
    info = os.path.join(path, "INFO")
    if not os.path.isfile(info):
        return ""
    for line in open(info, encoding="utf-8", errors="replace").read().splitlines():
        if line.startswith("name="):
            return line[5:].strip()
    return ""


def manifest_rows(root):
    for row in read_rows(os.path.join(root, "tools/svg/apps.tsv"), "\t"):
        yield row[0], row[5]


def entries(root):
    aliases = dict(read_rows(os.path.join(root, "tools/appreg/alias.tsv"), "\t"))
    seen = set()
    for row in read_rows(os.path.join(root, "tools/loader/apps.tab"), "|"):
        seen.add(row[0])
        yield row[0], row[6], icon_dir(root, row[0], aliases), row[3]
    for app in aliases:
        if app not in seen:
            d = icon_dir(root, app, aliases)
            yield app, "fenster", d, bundle_title(os.path.join(root, aliases[app]))
            seen.add(app)
    for app, path in manifest_rows(root):
        if app not in seen:
            seen.add(app)
            yield app, "fenster", os.path.join(root, path), bundle_title(os.path.join(root, path))


def main(argv):
    root, out = argv[0], argv[1]
    bad = 0
    for app, kind, d, title in entries(root):
        if d is None:
            print("no icon source for %s" % app)
            bad += 1
            continue
        target = os.path.join(out, "usr/share/appreg", app)
        os.makedirs(target, exist_ok=True)
        with open(os.path.join(target, "symbol"), "wb") as f:
            f.write(symjoin.joined(d))
        if title:
            with open(os.path.join(target, "title"), "w", encoding="utf-8") as f:
                f.write(title[:46] + "\n")
        canon = alias_target(root, app)
        if canon:
            with open(os.path.join(target, "alias"), "w") as f:
                f.write(canon + "\n")
        if kind == "konsole":
            with open(os.path.join(target, "console"), "w") as f:
                f.write("1\n")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
