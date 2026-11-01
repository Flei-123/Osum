#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import builtins
import collections
import io
import keyword
import os
import py_compile
import re
import subprocess
import sys
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import count  # noqa: E402
from dict import SEG  # noqa: E402

WORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
RESERVED = set(keyword.kwlist) | set(dir(builtins)) | {"self", "cls", "os", "sys", "re", "json", "math", "time", "random", "struct", "zlib", "hashlib", "subprocess", "collections", "itertools", "functools", "string", "socket", "select", "signal", "shutil", "tempfile", "glob", "copy", "array", "types", "io", "ast", "csv", "base64", "hmac", "binascii", "argparse", "datetime", "pathlib", "enum", "queue", "threading", "ctypes", "operator", "traceback", "textwrap", "unittest", "logging", "html", "heapq", "bisect", "fnmatch", "stat", "errno", "platform", "pickle", "gzip", "bz2", "lzma", "inspect", "dataclasses", "typing", "abc", "contextlib", "decimal", "fractions", "statistics", "secrets", "uuid", "urllib", "http", "ssl", "email", "numpy", "PIL", "Image", "np"}


def tracked_py():
    out = subprocess.run(["git", "ls-files", "*.py"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    allow = count.load_allow()
    return [f for f in out if not count.allowed(f, allow) and not f.startswith(count.SKIP_PREFIX) and not f.startswith("tools/wlan/")]


def translate(name):
    parts = re.split(r"(_+|[0-9]+)", name)
    out = []
    for p in parts:
        low = p.lower()
        if len(p) >= 3 and low in count.GERMAN and low in SEG and SEG[low] != low:
            t = SEG[low]
            if p.isupper():
                t = t.upper()
            elif p[:1].isupper() and not p[1:].isupper():
                t = t[:1].upper() + t[1:]
            out.append(t)
        else:
            out.append(p)
    return "".join(out)


def fstring_names(tok):
    m = re.match(r"^([A-Za-z]*)(\"\"\"|'''|\"|')", tok)
    if not m or "f" not in m.group(1).lower():
        return []
    body = tok[m.end():]
    names = []
    depth = 0
    i = 0
    cur = []
    while i < len(body):
        c = body[i]
        if depth == 0:
            if c == "{" and body[i:i + 2] == "{{":
                i += 2
                continue
            if c == "{":
                depth = 1
                cur = []
        else:
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    names.append("".join(cur))
            cur.append(c)
        i += 1
    return names


def rewrite_fstring(tok, fn):
    m = re.match(r"^([A-Za-z]*)(\"\"\"|'''|\"|')", tok)
    if not m or "f" not in m.group(1).lower():
        return tok
    out = []
    body = tok[m.end():]
    head = tok[:m.end()]
    depth = 0
    i = 0
    seg = []
    while i < len(body):
        c = body[i]
        if depth == 0:
            if body[i:i + 2] == "{{":
                out.append("{{")
                i += 2
                continue
            if c == "{":
                depth = 1
                out.append(c)
                seg = []
            else:
                out.append(c)
        else:
            if c == "{":
                depth += 1
                seg.append(c)
            elif c == "}":
                depth -= 1
                if depth == 0:
                    out.append(fn("".join(seg)) + "}")
                else:
                    seg.append(c)
            else:
                seg.append(c)
        i += 1
    return head + "".join(out)


def tokens(path):
    src = open(path, encoding="utf-8").read()
    return src, list(tokenize.generate_tokens(io.StringIO(src).readline))


def scan(files):
    names = collections.Counter()
    strings = []
    alltok = set()
    for f in files:
        try:
            src, toks = tokens(f)
        except Exception:
            continue
        for t in toks:
            if t.type == tokenize.NAME:
                alltok.add(t.string)
                if count.german_ident(t.string):
                    names[t.string] += 1
            elif t.type == tokenize.STRING:
                strings.append(t.string)
                for expr in fstring_names(t.string):
                    for w in WORD.findall(expr):
                        alltok.add(w)
                        if count.german_ident(w):
                            names[w] += 1
    return names, strings, alltok


def protected(names, strings):
    prot = set()
    blob = "\n".join(strings)
    for n in names:
        dash = n.replace("_", "-")
        if re.search(r"(?<![A-Za-z0-9_])(--?)?(%s|%s)(?![A-Za-z0-9_])" % (re.escape(n), re.escape(dash)), blob):
            for s in strings:
                if re.match(r"^[A-Za-z]*(\"\"\"|'''|\"|')", s) and "f" in re.match(r"^[A-Za-z]*", s).group(0).lower():
                    continue
                body = s.strip("'\"")
                if body in (n, dash, "--" + dash, "-" + dash) or ("{" + n) in s or ("%(" + n + ")") in s or (n + "=") in body.replace(" ", "") and len(body) < 60:
                    prot.add(n)
                    break
    return prot


def build_map(names, alltok, prot):
    mapping = {}
    used = set(alltok)
    for n in sorted(names):
        if n in prot:
            continue
        new = translate(n)
        if new == n:
            continue
        cand = new
        k = 2
        while cand in RESERVED or (cand in used and cand != n) or cand in mapping.values():
            cand = "%s_%d" % (new, k) if new not in RESERVED else "%s_" % new
            if cand in RESERVED or cand in used:
                cand = "%s_%d" % (new.rstrip("_"), k)
            k += 1
        mapping[n] = cand
        used.add(cand)
    return mapping


def apply_file(path, mapping):
    src, toks = tokens(path)
    lines = src.splitlines(keepends=True)
    edits = []
    for t in toks:
        if t.type == tokenize.NAME and t.string in mapping:
            edits.append((t.start, t.end, mapping[t.string]))
        elif t.type == tokenize.STRING:
            new = rewrite_fstring(t.string, lambda e: WORD.sub(lambda m: mapping.get(m.group(0), m.group(0)), e))
            if new != t.string:
                edits.append((t.start, t.end, new))
    if not edits:
        return False
    for (sr, sc), (er, ec), new in sorted(edits, reverse=True):
        if sr == er:
            ln = lines[sr - 1]
            lines[sr - 1] = ln[:sc] + new + ln[ec:]
        else:
            first = lines[sr - 1][:sc]
            last = lines[er - 1][ec:]
            lines[sr - 1:er] = [first + new + last]
    open(path, "w", encoding="utf-8").write("".join(lines))
    return True


EXTRA_SEG = {"kachel": "tile", "teile": "parts", "verteiler": "dispatch", "keine": "no", "ohne": "without", "schleife": "loop",
             "faktor": "factor", "je": "per", "lauf": "run", "schrift": "font", "stapel": "stack", "ersatz": "fallback",
             "reiter": "tab", "ausnahmen": "exceptions", "ausnahme": "exception", "taste": "key", "tasten": "keys"}


def foreign_modules(files):
    by_dir = {}
    for f in files:
        by_dir.setdefault(os.path.dirname(f), []).append(f)
    stems = {}
    for f in files:
        stems.setdefault(os.path.splitext(os.path.basename(f))[0], set()).add(os.path.dirname(f))
    out = set()
    pat = re.compile(r"^\s*(?:from\s+([A-Za-z_][A-Za-z0-9_]*)\s+import|import\s+([A-Za-z_][A-Za-z0-9_, ]*))", re.M)
    for f in files:
        try:
            src = open(os.path.join(ROOT, f), encoding="utf-8").read()
        except Exception:
            continue
        d = os.path.dirname(f)
        for m in pat.finditer(src):
            mods = [m.group(1)] if m.group(1) else [x.strip().split(" ")[0] for x in m.group(2).split(",")]
            for mod in mods:
                if mod in stems and (stems[mod] - {d}):
                    for dd in stems[mod]:
                        if dd != d:
                            out.add(os.path.join(dd, mod + ".py"))
    return out


def plan(files):
    by_dir = {}
    for f in files:
        by_dir.setdefault(os.path.dirname(f), []).append(f)
    shared = foreign_modules(files)
    shared_names = set()
    for f in shared:
        try:
            _, toks = tokens(os.path.join(ROOT, f))
        except Exception:
            continue
        for t in toks:
            if t.type == tokenize.NAME:
                shared_names.add(t.string)
    return by_dir, shared_names


def main():
    do = "--apply" in sys.argv
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    files = tracked_py()
    by_dir, shared_names = plan(files)
    for k, v in EXTRA_SEG.items():
        SEG.setdefault(k, v)
        count.GERMAN.add(k)
    total = 0
    bad = 0
    allmap = {}
    for d, fl in sorted(by_dir.items()):
        if only and not any(d == o or d.startswith(o.rstrip("/") + "/") for o in only):
            continue
        fl = [f for f in fl if os.path.exists(os.path.join(ROOT, f))]
        names, strings, alltok = scan(fl)
        prot = protected(names, strings) | (set(names) & shared_names)
        mapping = build_map(names, alltok, prot)
        total += len(mapping)
        allmap[d] = mapping
        print("%s: files %d, names %d, protected %d, renamed %d" % (d, len(fl), len(names), len(prot), len(mapping)))
        if not do:
            continue
        for f in fl:
            try:
                apply_file(os.path.join(ROOT, f), mapping)
            except Exception as e:
                print("skip", f, e)
        for f in fl:
            try:
                compile(open(os.path.join(ROOT, f), encoding="utf-8").read(), f, "exec")
            except Exception as e:
                bad += 1
                print("COMPILE FAIL", f, str(e)[:100])
    if do and os.environ.get("PYRN_MAP"):
        import json
        json.dump(allmap, open(os.environ["PYRN_MAP"], "w"))
    print("renamed %d, compile failures %d" % (total, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
