#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import ast
import io
import os
import re
import subprocess
import sys
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import count  # noqa: E402

KEEP = re.compile(r"^#(!|\s*SPDX|.*coding[:=]|\s*(noqa|type:|pragma|fmt:|pylint))")


class Dropper(ast.NodeTransformer):
    def generic_visit(self, node):
        super().generic_visit(node)
        for field in ("body", "orelse", "finalbody"):
            body = getattr(node, field, None)
            if isinstance(body, list):
                kept = [n for n in body if not (isinstance(n, ast.Expr) and isinstance(n.value, ast.Constant) and isinstance(n.value.value, str))]
                if not kept and body:
                    kept = [ast.Pass()]
                setattr(node, field, kept)
        return node


def norm(src):
    return ast.dump(Dropper().visit(ast.parse(src)))


def docstring_spans(src):
    tree = ast.parse(src)
    out = []
    for node in ast.walk(tree):
        for field in ("body", "orelse", "finalbody"):
            body = getattr(node, field, None)
            if not isinstance(body, list):
                continue
            for n in body:
                if isinstance(n, ast.Expr) and isinstance(n.value, ast.Constant) and isinstance(n.value.value, str):
                    out.append((n.lineno, n.end_lineno, n.col_offset, len(body) == 1))
    return out


def strip(src, docs):
    lines = src.splitlines(keepends=True)
    toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    for t in reversed(toks):
        if t.type == tokenize.COMMENT and not KEEP.match(t.string):
            r, c = t.start
            ln = lines[r - 1]
            head = ln[:c].rstrip()
            lines[r - 1] = (head + "\n") if head else ""
    if docs:
        for a, b, col, only in sorted(docstring_spans(src), reverse=True):
            first = lines[a - 1]
            if first[:col].strip():
                continue
            ind = first[:col]
            lines[a - 1:b] = [ind + "pass\n"] if only else []
    text = "".join(lines)
    text = re.sub(r"\n{3,}", "\n\n", text) if False else text
    return text


def files_in(prefixes):
    out = subprocess.run(["git", "ls-files", "*.py"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    allow = count.load_allow()
    out = [f for f in out if not count.allowed(f, allow) and not f.startswith(count.SKIP_PREFIX) and not f.startswith("tools/wlan/")]
    return [f for f in out if not prefixes or any(f == p or f.startswith(p.rstrip("/") + "/") for p in prefixes)]


def main():
    do = "--apply" in sys.argv
    prefixes = [a for a in sys.argv[1:] if not a.startswith("--")]
    changed = 0
    for f in files_in(prefixes):
        path = os.path.join(ROOT, f)
        try:
            src = open(path, encoding="utf-8").read()
            ast.parse(src)
        except Exception:
            continue
        docs = "__doc__" not in src
        new = strip(src, docs)
        if new == src:
            continue
        try:
            same = norm(new) == norm(src)
        except SyntaxError as e:
            print("SYNTAX", f, e)
            continue
        if not same:
            print("AST DIFF", f)
            continue
        changed += 1
        if do:
            open(path, "w", encoding="utf-8").write(new)
    print("changed", changed)


if __name__ == "__main__":
    main()
