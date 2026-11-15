import re
import sys
from pathlib import Path

FN = re.compile(r"^\s*(?:pub\s+)?fn\s+(\w+)\s*\(", re.M)
CALL = re.compile(r"\b(?:(\w+)\.)?(\w+)\s*\(")
PRIMITIVES = {"atomic", "irqlock", "fdlock", "fslock"}
KEYWORDS = {"if", "while", "fn", "asm", "return", "let", "var", "for", "match"}
TAKE_PATTERNS = [
    (re.compile(r"atomic\.lock_(?:take|try)\([^,]+,\s*atomic\.(L_\w+)"), None),
    (re.compile(r"irqlock\.enter\([^,]+,\s*atomic\.(L_\w+)"), None),
    (re.compile(r"\bfdlock\.enter\("), "L_FD"),
    (re.compile(r"\bfslock\.(?:enter|take)\("), "L_FS"),
]
GIVE_PATTERNS = [
    (re.compile(r"atomic\.lock_give\([^,]+,\s*atomic\.(L_\w+)"), None),
    (re.compile(r"irqlock\.leave\([^,]+,\s*atomic\.(L_\w+)"), None),
    (re.compile(r"\bfdlock\.leave\("), "L_FD"),
    (re.compile(r"\bfslock\.(?:leave|give)\("), "L_FS"),
]


def match_lock(patterns, line):
    for pattern, fixed in patterns:
        m = pattern.search(line)
        if m:
            return fixed or m.group(1)
    return None


def split_functions(text):
    marks = [(m.start(), m.group(1)) for m in FN.finditer(text)]
    for i, (start, name) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        yield name, text[start:end]


def load(root):
    funcs = {}
    by_name = {}
    for path in sorted(Path(root).rglob("*.fi")):
        if path.stem in PRIMITIVES:
            continue
        for name, body in split_functions(path.read_text(errors="replace")):
            key = f"{path.stem}.{name}"
            lines = [l.split("//")[0] for l in body.splitlines()[1:]]
            funcs[key] = {"path": str(path), "stem": path.stem, "lines": lines}
            by_name.setdefault(name, []).append(key)
    return funcs, by_name


def resolve(funcs, by_name, stem, qualifier, name):
    if qualifier:
        key = f"{qualifier}.{name}"
        return key if key in funcs else None
    own = f"{stem}.{name}"
    if own in funcs:
        return own
    owners = by_name.get(name, [])
    return owners[0] if len(owners) == 1 else None


def scan(funcs, by_name, summary):
    edges = {}
    result = {}
    for key, fn in funcs.items():
        held = []
        takes = set()
        for line in fn["lines"]:
            taken = match_lock(TAKE_PATTERNS, line)
            if taken:
                for h in held:
                    edges.setdefault((h, taken), set()).add(f"{key} direct")
                takes.add(taken)
                held.append(taken)
                continue
            given = match_lock(GIVE_PATTERNS, line)
            if given:
                if given in held:
                    held.remove(given)
                continue
            for m in CALL.finditer(line):
                if m.group(2) in KEYWORDS or m.group(1) in PRIMITIVES:
                    continue
                callee = resolve(funcs, by_name, fn["stem"], m.group(1), m.group(2))
                if not callee or callee == key:
                    continue
                info = summary.get(callee, {"takes": set(), "returns": [], "gives": []})
                for lock in info["takes"]:
                    takes.add(lock)
                    for h in held:
                        if h != lock:
                            edges.setdefault((h, lock), set()).add(f"{key} -> {callee}")
                for lock in info["returns"]:
                    held.append(lock)
                for lock in info["gives"]:
                    if lock in held:
                        held.remove(lock)
        result[key] = {"takes": takes, "returns": list(held), "gives": gives_of(fn)}
    return edges, result


def gives_of(fn):
    taken = set()
    gives = []
    for line in fn["lines"]:
        t = match_lock(TAKE_PATTERNS, line)
        if t:
            taken.add(t)
        g = match_lock(GIVE_PATTERNS, line)
        if g and g not in taken:
            gives.append(g)
    return gives


def main():
    root = sys.argv[1]
    funcs, by_name = load(root)
    summary = {}
    for _ in range(6):
        edges, summary = scan(funcs, by_name, summary)
    for (a, b), where in sorted(edges.items()):
        print(f"{a} -> {b}  ({len(where)}) e.g. {sorted(where)[0]}")
    leaf_locks = sys.argv[2:]
    leaf_bad = [(a, b) for (a, b) in edges if a in leaf_locks]
    for a, b in leaf_bad:
        print(f"LEAF VIOLATION {a} -> {b}: {sorted(edges[(a, b)])[0]}")
    bad = [(a, b) for (a, b) in edges if (b, a) in edges and a < b and a in leaf_locks + [b][:0] or (b in leaf_locks and (b, a) in edges)]
    for a, b in bad:
        print(f"CYCLE {a} <-> {b}")
        for w in sorted(edges[(a, b)])[:4]:
            print(f"  {a}->{b}: {w}")
        for w in sorted(edges[(b, a)])[:4]:
            print(f"  {b}->{a}: {w}")
    sys.exit(1 if bad or leaf_bad else 0)


main()
