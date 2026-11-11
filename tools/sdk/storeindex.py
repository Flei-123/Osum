#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import hashlib
import json
import os
import sys

from manifest import lint, normalize

INDEX_SCHEMA = "orientos.store-index/2"
PACKAGE_FIELDS = ("id", "name", "info", "keys", "version", "revision", "kind", "outputs", "menu",
                  "permissions", "services", "icon", "min_os", "needs", "native", "web")


def info_files(paths):
    out = []
    for p in paths:
        if os.path.isfile(p):
            out.append(p)
            continue
        for name in sorted(os.listdir(p)):
            candidate = os.path.join(p, name, "INFO")
            if os.path.isfile(candidate):
                out.append(candidate)
    return out


def load(info, system):
    project = os.path.dirname(os.path.abspath(info))
    rep, fields = lint(info, project, system=system)
    if rep.errors:
        raise SystemExit("storeindex: %s refused: %s" % (info, "; ".join(rep.errors)))
    return normalize(fields)


def attach_file(entry, opk_dir):
    name = "%s-%s.opk" % (entry["id"].rsplit(".", 1)[-1], entry["version"])
    path = os.path.join(opk_dir, name)
    if not os.path.isfile(path):
        return False
    data = open(path, "rb").read()
    entry["file"] = {"name": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
    return True


def build_index(infos, system=False, opk_dir=None, require_files=False):
    seen_ids, seen_short, packages = {}, {}, []
    for info in infos:
        m = load(info, system)
        short = m["id"].rsplit(".", 1)[-1]
        if m["id"] in seen_ids or short in seen_short:
            raise SystemExit("storeindex: %s duplicates %s" % (info, seen_ids.get(m["id"]) or seen_short[short]))
        seen_ids[m["id"]] = seen_short[short] = info
        entry = {k: m[k] for k in PACKAGE_FIELDS if k in m}
        if opk_dir and not attach_file(entry, opk_dir) and require_files:
            raise SystemExit("storeindex: no package file for %s %s" % (m["id"], m["version"]))
        packages.append(entry)
    packages.sort(key=lambda e: e["id"])
    return {"schema": INDEX_SCHEMA, "packages": packages}


def main(argv):
    ap = argparse.ArgumentParser(prog="storeindex.py")
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--system", action="store_true")
    ap.add_argument("--opk")
    ap.add_argument("--require-files", action="store_true")
    ap.add_argument("--out")
    args = ap.parse_args(argv[1:])
    index = build_index(info_files(args.paths), args.system, args.opk, args.require_files)
    text = json.dumps(index, indent=1, sort_keys=True) + "\n"
    if args.out:
        open(args.out, "w").write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
