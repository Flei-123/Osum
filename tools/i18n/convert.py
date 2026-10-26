#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def read_table(lang):
    table = {}
    for line in open(os.path.join(root, "locale", lang, "messages"), encoding="utf-8"):
        if line.startswith("#") or " = " not in line:
            continue
        key, value = line.rstrip("\n").split(" = ", 1)
        table[key.strip()] = value
    return table


def convert(source, spec_lines):
    path = os.path.join(root, source)
    text = open(path, encoding="utf-8").read()
    de = read_table("de")
    added = []
    report = []
    for spec in spec_lines:
        spec = spec.strip("\n").strip()
        spec = spec.replace("\\_", "\x00")
        if not spec or spec.startswith("#"):
            continue
        name, key, english = spec.split("|", 2)
        english = english.replace("\x00", " ")
        decl = re.compile(
            r'^(?P<head>[ \t]*(?:static mut |var |let )?)%s: \[u8; \d+\] = "(?P<body>.*)"[ \t]*$' % re.escape(name),
            re.M)
        match = decl.search(text)
        if not match:
            report.append("NO DECL %s" % name)
            continue
        body = match.group("body")
        while body.endswith("\\0"):
            body = body[:-2]
        if "\\0" in body:
            report.append("MULTI %s" % name)
            continue
        german = body
        reuse = key in de
        if not reuse:
            added.append((key, english, german))
        new_decl = '%s%s: [u8; %d] = "%s\\0"' % (match.group("head"), name, len(key) + 1, key)
        text = text[:match.start()] + new_decl + text[match.end():]
        use = re.compile(r'\(&%s\[(?:\(0\)|0)(?: as usize)?\]\) as u64' % re.escape(name))
        text, count = use.subn(lambda m: "msg.get(%s)" % m.group(0), text)
        rest = len(re.findall(r'\b%s\b' % re.escape(name), text)) - 1 - count
        report.append("%s -> %s uses=%d other=%d%s" % (name, key, count, rest, " reuse" if reuse else ""))
    if "import msg" not in text:
        imports = list(re.finditer(r'^import [\w.]+[ \t]*$', text, re.M))
        last = imports[-1]
        text = text[:last.end()] + "\nimport msg" + text[last.end():]
    open(path, "w", encoding="utf-8").write(text)
    return added, report


def main():
    source = sys.argv[1]
    spec = open(sys.argv[2], encoding="utf-8").read().split("\n")
    added, report = convert(source, spec)
    for line in report:
        print(line)
    if added:
        header = "\n# %s\n" % os.path.basename(source)
        with open(os.path.join(root, "locale", "en", "messages"), "a", encoding="utf-8") as f:
            f.write(header)
            for key, english, german in added:
                f.write("%s = %s\n" % (key, english))
        with open(os.path.join(root, "locale", "de", "messages"), "a", encoding="utf-8") as f:
            f.write(header)
            for key, english, german in added:
                f.write("%s = %s\n" % (key, german))


main()
