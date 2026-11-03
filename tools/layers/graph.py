import collections
import os
import re

ROOTS = ("lib", "kernel")
IMPORT = re.compile(rb"^import\s+([A-Za-z0-9_.]+)", re.M)
FALLBACK_DIRS = ("lib", "kernel/user", "kernel")


def collect(root):
    found = []
    for top in ROOTS:
        base = os.path.join(root, top)
        for dirpath, _, names in os.walk(base):
            for name in names:
                if name.endswith(".fi"):
                    found.append(os.path.relpath(os.path.join(dirpath, name), root))
    return sorted(found)


def candidates(path, rel):
    out = [os.path.join(os.path.dirname(path), rel)]
    parent = os.path.dirname(path)
    while parent:
        out.append(os.path.join(parent, rel))
        parent = os.path.dirname(parent)
    out.extend(os.path.join(d, rel) for d in FALLBACK_DIRS)
    return out


def build(root):
    files = collect(root)
    known = set(files)
    by_name = collections.defaultdict(list)
    for path in files:
        by_name[os.path.basename(path)].append(path)
    edges = collections.defaultdict(set)
    external = collections.Counter()
    for path in files:
        with open(os.path.join(root, path), "rb") as handle:
            data = handle.read()
        for match in IMPORT.finditer(data):
            dotted = match.group(1).decode()
            rel = dotted.replace(".", "/") + ".fi"
            target = next((c for c in candidates(path, rel) if c in known), None)
            if target is None and "." not in dotted and len(by_name[rel]) == 1:
                target = by_name[rel][0]
            if target is None:
                external[dotted] += 1
            elif target != path:
                edges[path].add(target)
    return files, edges, external


def components(nodes, edges):
    index = {}
    low = {}
    stack = []
    on = set()
    out = []
    counter = [0]

    def visit(start):
        work = [(start, iter(sorted(edges.get(start, ()))))]
        index[start] = low[start] = counter[0]
        counter[0] += 1
        stack.append(start)
        on.add(start)
        while work:
            node, it = work[-1]
            advanced = False
            for nxt in it:
                if nxt not in index:
                    index[nxt] = low[nxt] = counter[0]
                    counter[0] += 1
                    stack.append(nxt)
                    on.add(nxt)
                    work.append((nxt, iter(sorted(edges.get(nxt, ())))))
                    advanced = True
                    break
                if nxt in on:
                    low[node] = min(low[node], index[nxt])
            if advanced:
                continue
            work.pop()
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[node])
            if low[node] == index[node]:
                comp = []
                while True:
                    top = stack.pop()
                    on.discard(top)
                    comp.append(top)
                    if top == node:
                        break
                if len(comp) > 1:
                    out.append(sorted(comp))

    for node in sorted(nodes):
        if node not in index:
            visit(node)
    return sorted(out)
