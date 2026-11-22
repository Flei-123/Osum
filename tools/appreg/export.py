#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import json
import os
import subprocess
import sys

MANIFEST = "tools/svg/apps.tsv"
ALIASES = "tools/appreg/alias.tsv"
SOURCE_DIRS = {"=": "assets/icons/app", "@": "assets/icons/brand"}
SCHEMA_VERSION = 1


class Tree:
    def __init__(self, root, ref):
        self.root = root
        self.ref = ref

    def read(self, path):
        if self.ref:
            out = subprocess.run(["git", "-C", self.root, "show", "%s:%s" % (self.ref, path)], capture_output=True)
            return out.stdout.decode("utf-8", "replace") if out.returncode == 0 else None
        full = os.path.join(self.root, path)
        return open(full, encoding="utf-8", errors="replace").read() if os.path.isfile(full) else None

    def commit(self):
        out = subprocess.run(["git", "-C", self.root, "rev-parse", "--short=9", self.ref or "HEAD"], capture_output=True)
        return out.stdout.decode().strip() if out.returncode == 0 else ""


def rows(text):
    for line in (text or "").splitlines():
        if line.strip() and not line.startswith("#"):
            yield line.split("\t")


def bundle_title(tree, folder):
    for line in (tree.read(folder + "/INFO") or "").splitlines():
        if line.startswith("name="):
            return line[5:].strip()
    return ""


def source_path(spec):
    folder = SOURCE_DIRS.get(spec[0])
    if folder is None:
        raise SystemExit("icon source %r has an unknown prefix" % spec)
    return "%s/%s.svg" % (folder, spec[1:])


def collect(tree):
    manifest = list(rows(tree.read(MANIFEST)))
    by_folder = {row[5]: row for row in manifest}
    entries = {}
    for row in manifest:
        entries[row[0]] = {"source": source_path(row[1]), "title": bundle_title(tree, row[5]), "alias_of": None}
    for row in rows(tree.read(ALIASES)):
        target = by_folder.get(row[1])
        if target is None or row[0] in entries:
            continue
        entries[row[0]] = {"source": source_path(target[1]), "title": entries[target[0]]["title"], "alias_of": target[0]}
    return entries


def export(tree, out):
    entries = collect(tree)
    os.makedirs(out, exist_ok=True)
    index = {"schema_version": SCHEMA_VERSION, "commit": tree.commit(), "icons": {}}
    for app_id in sorted(entries):
        entry = entries[app_id]
        svg = tree.read(entry["source"])
        if svg is None:
            raise SystemExit("%s: central source %s is missing" % (app_id, entry["source"]))
        with open(os.path.join(out, app_id + ".svg"), "w", encoding="utf-8") as f:
            f.write(svg)
        index["icons"][app_id] = {"file": app_id + ".svg", **entry}
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(index, f, indent=1, sort_keys=True)
        f.write("\n")
    return index


def main(argv):
    parser = argparse.ArgumentParser(description="Export app id -> icon SVG from the registry sources")
    parser.add_argument("--repo", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    parser.add_argument("--ref", default="")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    index = export(Tree(os.path.abspath(args.repo), args.ref), args.out)
    print("exported %d icons (commit %s)" % (len(index["icons"]), index["commit"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
