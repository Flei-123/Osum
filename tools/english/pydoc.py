#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import ast
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import count  # noqa: E402
import pyfinal  # noqa: E402
import pyrn  # noqa: E402
from dict import SEG  # noqa: E402

GERMAN_DOC = re.compile(r"\b(der|die|das|und|nicht|ein|eine|wird|mit|fuer|ist|zum|zur|von|den|dem|auf|aus|oder|alle|jede|jedes)\b")
MAPPING = pyfinal.load_map()
MAPPING.update({k: v for k, v in pyrn.EXTRA_SEG.items()})
LOWER = {k.lower(): v for k, v in MAPPING.items()}


def tr_word(w):
    low = w.lower()
    if low in LOWER:
        return LOWER[low]
    return pyrn.translate(w)


def tr_line(line):
    return re.sub(r"[A-Za-z_][A-Za-z0-9_]*", lambda m: tr_word(m.group(0)).replace("_", "-") if line[max(0, m.start() - 2):m.start()] == "--" else tr_word(m.group(0)), line)


def usage_lines(doc, base):
    out = []
    for ln in doc.splitlines():
        s = ln.strip()
        if not s or GERMAN_DOC.search(s.lower()) and not s.startswith(base):
            continue
        if s.startswith(base) or s.startswith("usage") or re.match(r"^\[?--?[A-Za-z]", s) or ("<" in s and ">" in s) or s.startswith("python"):
            out.append(tr_line(ln.rstrip()))
    return out


def main():
    do = "--apply" in sys.argv
    n = 0
    for f in pyfinal.german_files() if False else subprocess.run(["git", "ls-files", "*.py"], cwd=ROOT, capture_output=True, text=True).stdout.split():
        if f.startswith(("vendor/", "tools/wlan/", "tools/usbnet/", "tools/english/")):
            continue
        p = os.path.join(ROOT, f)
        src = open(p, encoding="utf-8").read()
        try:
            tree = ast.parse(src)
        except Exception:
            continue
        d = ast.get_docstring(tree, clean=False)
        if not d or not GERMAN_DOC.search(d.lower()):
            continue
        node = tree.body[0]
        base = os.path.basename(f)
        lines = usage_lines(d, base)
        if lines:
            body = "Usage:\n" + "\n".join(("    " + x.strip()) if not x.strip().startswith(base) else "    " + x.strip() for x in lines[:12]) + "\n"
        else:
            body = base + "\n"
        new = '"""' + body.replace('"""', "'''") + '"""\n'
        sl = src.splitlines(keepends=True)
        sl[node.lineno - 1:node.end_lineno] = [new]
        n += 1
        if do:
            open(p, "w", encoding="utf-8").write("".join(sl))
            compile("".join(sl), f, "exec")
    print("docstrings", n)


if __name__ == "__main__":
    main()
