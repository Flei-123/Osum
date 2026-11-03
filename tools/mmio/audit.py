import re
import subprocess
import sys

FN_RE = re.compile(r"^(?:export\s+)?(?:pub\s+)?fn\s+(\w+)\s*\(")
VOLATILE_RE = re.compile(r"__mmio_(?:read|write)\d+|\bkstate\.(?:get|set)8\b|\bregio\.\w+")
PLAIN_RE = re.compile(r"\b(?:octets|ascii|numeric|text)\.\w+")
CALL_RE = re.compile(r"\b(\w+)\s*\(")


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, errors="replace").stdout


def parse(text):
    funcs = {}
    name = None
    start = 0
    lines = text.split("\n")
    for i, line in enumerate(lines):
        m = FN_RE.match(line)
        if m:
            name = m.group(1)
            start = i
        elif name and line.startswith("}"):
            funcs[name] = (start + 1, "\n".join(lines[start:i + 1]))
            name = None
    return funcs


QUAL_RE = re.compile(r"\b(\w+)\.(\w+)\s*\(")
UNQ_RE = re.compile(r"(?<![\w.])(\w+)\s*\(")


def load_tree(rev, paths):
    tree = {}
    for p in paths:
        t = git("show", f"{rev}:{p}")
        if t:
            tree[p] = parse(t)
    return tree


def stem(path):
    return path.rsplit("/", 1)[-1][:-3]


def build_volatile(tree):
    by_stem = {}
    for p in tree:
        by_stem.setdefault(stem(p), []).append(p)
    vol = set()
    for p, funcs in tree.items():
        for n, (_, b) in funcs.items():
            if VOLATILE_RE.search(b):
                vol.add((p, n))
    changed = True
    while changed:
        changed = False
        for p, funcs in tree.items():
            for n, (_, b) in funcs.items():
                if (p, n) in vol:
                    continue
                hit = False
                for c in UNQ_RE.findall(b):
                    if c in funcs and (p, c) in vol and c != n:
                        hit = True
                        break
                if not hit:
                    for m, f in QUAL_RE.findall(b):
                        for q in by_stem.get(m, []):
                            if (q, f) in vol:
                                hit = True
                                break
                        if hit:
                            break
                if hit:
                    vol.add((p, n))
                    changed = True
    return vol, by_stem


def why(path, funcs, body, vol, by_stem):
    out = set()
    if VOLATILE_RE.search(body):
        out.add("direct")
    for c in UNQ_RE.findall(body):
        if c in funcs and (path, c) in vol:
            out.add(c)
    for m, f in QUAL_RE.findall(body):
        for q in by_stem.get(m, []):
            if (q, f) in vol:
                out.add(m + "." + f)
    return sorted(out)


def line_volatile_count(path, funcs, line, vol, by_stem):
    if FN_RE.match(line):
        return 0
    total = len(VOLATILE_RE.findall(line))
    for c in UNQ_RE.findall(line):
        if c in funcs and (path, c) in vol:
            total += 1
    for m, f in QUAL_RE.findall(line):
        if m in ("kstate", "regio"):
            continue
        for q in by_stem.get(m, []):
            if (q, f) in vol:
                total += 1
                break
    return total


def line_volatile(path, funcs, line, vol, by_stem):
    if VOLATILE_RE.search(line):
        return True
    for c in UNQ_RE.findall(line):
        if c in funcs and (path, c) in vol and not FN_RE.match(line):
            return True
    for m, f in QUAL_RE.findall(line):
        for q in by_stem.get(m, []):
            if (q, f) in vol:
                return True
    return False


def main():
    old, new = sys.argv[1], sys.argv[2]
    all_paths = [p for p in git("ls-tree", "-r", "--name-only", new).split("\n") if p.endswith(".fi")]
    all_paths += [p for p in git("ls-tree", "-r", "--name-only", old).split("\n") if p.endswith(".fi") and p not in all_paths]
    changed = set(git("diff", "--name-only", old, new).split())
    otree = load_tree(old, all_paths)
    ntree = load_tree(new, all_paths)
    ov, os_ = build_volatile(otree)
    nv, ns = build_volatile(ntree)
    for p in sorted(changed):
        if p not in otree:
            continue
        of = otree[p]
        nf = ntree.get(p, {})
        for n, (line, body) in sorted(of.items(), key=lambda x: x[1][0]):
            if n not in nf:
                continue
            ol = body.split("\n")
            nl = nf[n][1].split("\n")
            sm = difflib.SequenceMatcher(None, ol, nl, autojunk=False)
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag != "replace":
                    continue
                olds = [(i, ol[i]) for i in range(i1, i2) if line_volatile(p, of, ol[i], ov, os_)]
                if not olds:
                    continue
                news = [nl[j] for j in range(j1, j2)]
                nvols = sum(1 for x in news if line_volatile(p, nf, x, nv, ns))
                if nvols >= len(olds):
                    continue
                for i, t in olds:
                    print("\t".join([p, str(line + i), n, t.strip(), " | ".join(x.strip() for x in news)]))
    for p in sorted(changed):
        if p not in otree:
            continue
        for n, (line, body) in otree[p].items():
            if n not in ntree.get(p, {}) and (p, n) in ov:
                print("\t".join([p, str(line), n, "REMOVED-FN", "", ""]))


import difflib


def count_report():
    old, new = sys.argv[1], sys.argv[2]
    all_paths = [p for p in git("ls-tree", "-r", "--name-only", new).split("\n") if p.endswith(".fi")]
    all_paths += [p for p in git("ls-tree", "-r", "--name-only", old).split("\n") if p.endswith(".fi") and p not in all_paths]
    changed = set(git("diff", "--name-only", old, new).split())
    otree = load_tree(old, all_paths)
    ntree = load_tree(new, all_paths)
    ov, os_ = build_volatile(otree)
    nv, ns = build_volatile(ntree)
    for p in sorted(changed):
        if p not in otree:
            continue
        of = otree[p]
        nf = ntree.get(p, {})
        for n, (line, body) in of.items():
            if n not in nf:
                continue
            oc = sum(line_volatile_count(p, of, x, ov, os_) for x in body.split("\n"))
            nc = sum(line_volatile_count(p, nf, x, nv, ns) for x in nf[n][1].split("\n"))
            if nc < oc:
                print("\t".join([p, str(line), n, str(oc), str(nc)]))


if len(sys.argv) > 3 and sys.argv[3] == "counts":
    count_report()
else:
    main()
