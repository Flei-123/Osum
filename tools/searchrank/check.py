#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def last_search(lines, query):
    start = None
    for i, line in enumerate(lines):
        if line.startswith("launcher: suche [%s]" % query):
            start = i
    if start is None:
        return None
    head = lines[start]
    best = ""
    apps = []
    files = []
    settings = []
    for line in lines[start + 1:]:
        if line.startswith("launcher: suche ["):
            break
        m = re.match(r"launcher: treffer i=(\d+) name=\[(.*)\] exec=\[(.*)\]", line)
        if m:
            apps.append((m.group(2), m.group(3)))
        m = re.match(r"launcher: best name=\[(.*)\]", line)
        if m:
            best = m.group(1)
        m = re.match(r"launcher: setting \[(.*)\]", line)
        if m:
            settings.append(m.group(1))
        m = re.match(r"launcher: file i=(\d+) name=\[(.*)\]", line)
        if m:
            files.append(m.group(2))
    return head, apps, files, best, settings


def main():
    lines = [l.rstrip("\n") for l in open(sys.argv[1], errors="replace")]
    query = sys.argv[2]
    found = last_search(lines, query)
    if found is None:
        print("missing")
        return 1
    head, apps, files, best, settings = found
    print("head=%s" % head)
    print("apps=%s" % "|".join(n for n, _ in apps))
    print("files=%s" % "|".join(files))
    print("best=%s" % best)
    print("settings=%s" % "|".join(settings))
    print("first_app=%s" % (apps[0][0] if apps else ""))
    print("first_exec=%s" % (apps[0][1] if apps else ""))
    return 0


sys.exit(main())
