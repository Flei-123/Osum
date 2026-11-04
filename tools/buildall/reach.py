import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IMPORT = re.compile(rb"^\s*import\s+([A-Za-z0-9_.]+)", re.M)
SOURCE_DIRS = ("kernel",)


def collect(root):
    by_name = {}
    for base in SOURCE_DIRS:
        for dirpath, _, names in os.walk(os.path.join(root, base)):
            for n in names:
                if n.endswith(".fi"):
                    rel = os.path.relpath(os.path.join(dirpath, n), root)
                    by_name.setdefault(n[:-3], []).append(rel)
    return by_name


def imports_of(root, rel):
    with open(os.path.join(root, rel), "rb") as fh:
        data = fh.read()
    return [m.decode().split(".")[-1] for m in IMPORT.findall(data)]


def reachable(root, roots, by_name):
    seen = set()
    stack = list(roots)
    while stack:
        rel = stack.pop()
        if rel in seen:
            continue
        seen.add(rel)
        for name in imports_of(root, rel):
            for target in by_name.get(name, []):
                stack.append(target)
    return seen


def main():
    result_file, root = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else ROOT)
    ok, fail = [], []
    for line in open(result_file, encoding="utf-8"):
        rel, status = line.split()
        (ok if status == "ok" else fail).append(rel)
    by_name = collect(root)
    covered = reachable(root, ok, by_name)
    orphans = sorted(f for f in fail if f not in covered)
    modules = sorted(f for f in fail if f in covered)
    print("\n".join(orphans))
    sys.stderr.write("failing=%d verified_via_importer=%d orphan=%d\n" % (len(fail), len(modules), len(orphans)))


main()
