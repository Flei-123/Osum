#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import fnmatch
import os
import re
import subprocess
import sys

PATTERN = re.compile(r"orientos|xoffi|orient\s?os", re.IGNORECASE)
SCAN_TOP = ["kernel", "lib", "locale", "assets", "etc", "pakete", "pkg", "sdk", "module",
            "wasm-module", "bench", "tests", "tools", "pruef", "test.sh", "marke.conf"]
SKIP_SUFFIX = (".md", ".png", ".ppm", ".img", ".xz", ".gz", ".bin", ".ttf", ".otf", ".woff", ".woff2", ".ico", ".jpg", ".pdf", ".osp")
HASH_SUFFIX = (".sh", ".py", ".ps1", ".conf", ".toml", ".mk", ".tsv", ".in", ".cfg", ".yml", ".yaml")
SLASH_SUFFIX = (".fi", ".c", ".h", ".cc", ".cpp", ".mjs", ".js", ".rs", ".s", ".S")


def load_allow(path):
    rules = []
    if not os.path.isfile(path):
        return rules
    with open(path, encoding="utf-8") as handle:
        for number, raw in enumerate(handle, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != 3 or not fields[2].strip():
                sys.exit("allow file %s:%d: need glob<TAB>regex<TAB>reason" % (path, number))
            glob, regex, reason = fields
            rules.append((glob.strip(), None if regex.strip() == "*" else re.compile(regex.strip(), re.IGNORECASE)))
    return rules


def allowed(rules, rel, line):
    for glob, regex in rules:
        if fnmatch.fnmatch(rel, glob) and (regex is None or regex.search(line)):
            return True
    return False


def comment_only(rel, line):
    stripped = line.strip()
    if rel.endswith(HASH_SUFFIX) or os.path.basename(rel) in ("Makefile", "test.sh"):
        if stripped.startswith("#"):
            return True
    if rel.endswith(SLASH_SUFFIX):
        if stripped.startswith(("//", "/*", "*")):
            return True
    return False


def strip_trailing_comment(rel, line):
    if rel.endswith(SLASH_SUFFIX):
        match = re.search(r"\s//\s", line)
        if match and '"' not in line[match.start():]:
            return line[:match.start()]
    return line


def list_files(root):
    if os.path.isdir(os.path.join(root, ".git")) or os.path.isfile(os.path.join(root, ".git")):
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True).stdout
        names = [n.decode("utf-8", "replace") for n in out.split(b"\0") if n]
    else:
        names = []
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d != ".git"]
            for name in files:
                names.append(os.path.relpath(os.path.join(base, name), root))
    return [n for n in names if n.split("/")[0] in SCAN_TOP]


def scan(root, rules, include_comments):
    hits = []
    for rel in list_files(root):
        if rel.endswith(SKIP_SUFFIX):
            continue
        full = os.path.join(root, rel)
        if not os.path.isfile(full) or os.path.islink(full):
            continue
        try:
            with open(full, "rb") as handle:
                data = handle.read()
        except OSError:
            continue
        if b"\0" in data[:4096]:
            continue
        for number, raw in enumerate(data.decode("utf-8", "replace").split("\n"), 1):
            if not PATTERN.search(raw):
                continue
            if not include_comments:
                if comment_only(rel, raw):
                    continue
                raw_code = strip_trailing_comment(rel, raw)
                if not PATTERN.search(raw_code):
                    continue
            if allowed(rules, rel, raw):
                continue
            hits.append((rel, number, raw.strip()[:140]))
    return hits


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--allow", default=None)
    parser.add_argument("--comments", action="store_true")
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    root = os.path.abspath(args.root)
    allow = args.allow or os.path.join(root, "tools", "brandcheck", "allow.txt")
    hits = scan(root, load_allow(allow), args.comments)
    if args.summary:
        counts = {}
        for rel, _, _ in hits:
            key = "/".join(rel.split("/")[:2])
            counts[key] = counts.get(key, 0) + 1
        for key, count in sorted(counts.items(), key=lambda item: -item[1]):
            print("%5d %s" % (count, key))
    else:
        for rel, number, text in hits:
            print("%s:%d: %s" % (rel, number, text))
    print("brandcheck: %d hits" % len(hits), file=sys.stderr)
    sys.exit(1 if hits else 0)


if __name__ == "__main__":
    main()
