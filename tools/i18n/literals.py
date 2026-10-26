#!/usr/bin/env python3
import os
import sys

root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def apply(source, spec_path):
    path = os.path.join(root, source)
    text = open(path, encoding="utf-8").read()
    en_rows = []
    de_rows = []
    seen = set()
    for raw in open(spec_path, encoding="utf-8").read().split("\n"):
        if not raw.strip() or raw.startswith("#"):
            continue
        parts = raw.split("|")
        german, key, english = parts[0], parts[1], parts[2]
        proper = parts[3] if len(parts) > 3 else german
        quoted = '"%s"' % german
        count = text.count(quoted)
        if count == 0:
            print("MISSING %s" % german)
            continue
        text = text.replace(quoted, '"%s"' % key)
        print("%s -> %s (%d)" % (german, key, count))
        if key not in seen:
            seen.add(key)
            en_rows.append("%s = %s" % (key, english))
            de_rows.append("%s = %s" % (key, proper))
    open(path, "w", encoding="utf-8").write(text)
    header = "\n# %s\n" % os.path.basename(source)
    for lang, rows in (("en", en_rows), ("de", de_rows)):
        with open(os.path.join(root, "locale", lang, "messages"), "a", encoding="utf-8") as f:
            f.write(header + "\n".join(rows) + "\n")


apply(sys.argv[1], sys.argv[2])
