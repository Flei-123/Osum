import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import findings
import graph
import layermap

BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "baseline.json")
LISTS = ("up_edges", "cycle_files", "giants", "loose_root")
COUNTS = ("dup_groups", "shared_in_app_dir")


def unit_of(path):
    parts = path.split("/")
    if parts[0] == "kernel" and len(parts) > 2 and parts[1] == "user":
        return "/".join(parts[:3]) if len(parts) > 3 else "kernel/user"
    return "/".join(parts[:2]) if len(parts) > 2 else parts[0]


def analyse(root, rules_file):
    order, rules = layermap.load(rules_file)
    rank = {name: i for i, name in enumerate(order)}
    files, edges, external = graph.build(root)
    layer = {p: layermap.layer_of(p, rules) for p in files}
    unmapped = sorted(p for p, v in layer.items() if v is None)
    up = []
    for src, targets in edges.items():
        for dst in targets:
            if layer[src] and layer[dst] and rank[layer[src]] < rank[layer[dst]]:
                up.append(f"{src} -> {dst} [{layer[src]} < {layer[dst]}]")
    cycles = graph.components(files, edges)
    unit_edges = collections.defaultdict(set)
    for src, targets in edges.items():
        for dst in targets:
            if unit_of(src) != unit_of(dst):
                unit_edges[unit_of(src)].add(unit_of(dst))
    dups = findings.duplicates(root, files)
    return {
        "order": order,
        "files": files,
        "layer": layer,
        "edges": edges,
        "external": external,
        "unmapped": unmapped,
        "up_edges": sorted(up),
        "cycles": cycles,
        "cycle_files": sorted({p for c in cycles for p in c}),
        "unit_cycles": graph.components({unit_of(p) for p in files}, unit_edges),
        "giants": findings.giants(root, files),
        "loose_root": findings.loose_root(root),
        "dups": dups,
        "dup_groups": len(dups),
        "shared_in_app_dir": len(findings.shared_in_app_dir(files, edges)),
    }


def table(result):
    rows = collections.defaultdict(lambda: [0, "", 0])
    for path in result["files"]:
        unit = unit_of(path)
        rows[unit][0] += 1
        rows[unit][1] = result["layer"][path]
    print("| unit | layer | files |")
    print("|---|---|---|")
    for unit in sorted(rows, key=lambda u: (result["order"].index(rows[u][1]), u)):
        print(f"| {unit} | {rows[unit][1]} | {rows[unit][0]} |")


def snapshot(result):
    out = {key: result[key] for key in LISTS}
    out.update({key: result[key] for key in COUNTS})
    return out


def compare(result, base):
    problems = []
    if result["unmapped"]:
        problems.append(("unmapped file (add a rule to tools/layers/layers.tsv)", result["unmapped"]))
    for key in LISTS:
        new = sorted(set(result[key]) - set(base.get(key, [])))
        if new:
            problems.append((f"new {key}", new))
    for key in COUNTS:
        if result[key] > base.get(key, 0):
            problems.append((f"{key} grew", [f"{base.get(key, 0)} -> {result[key]}"]))
    return problems


def summary(result):
    per = collections.Counter(result["layer"].values())
    parts = [f"{name}={per[name]}" for name in sorted(per, key=str)]
    print("files per layer: " + " ".join(parts))
    print(f"upward imports: {len(result['up_edges'])}")
    print(f"files in import cycles: {len(result['cycle_files'])} ({len(result['cycles'])} cycles)")
    print(f"directory units in cycles: {sum(len(c) for c in result['unit_cycles'])} ({len(result['unit_cycles'])} groups)")
    print(f"giant files (> {findings.GIANT_LINES} lines): {len(result['giants'])}")
    print(f"loose files in repo root: {len(result['loose_root'])}")
    print(f"duplicated function groups: {result['dup_groups']}")
    print(f"shared modules inside kernel/user: {result['shared_in_app_dir']}")


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=("check", "update", "report", "dump", "table"))
    ap.add_argument("--root", default=os.getcwd())
    ap.add_argument("--rules", default=layermap.FILE)
    ap.add_argument("--baseline", default=BASELINE)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args(argv)
    result = analyse(args.root, args.rules)
    if args.mode == "report":
        summary(result)
        return 0
    if args.mode == "table":
        table(result)
        return 0
    if args.mode == "dump":
        print(json.dumps(snapshot(result), indent=1))
        return 0
    base = {}
    if os.path.exists(args.baseline):
        with open(args.baseline) as handle:
            base = json.load(handle)
    problems = compare(result, base)
    if args.mode == "update":
        if problems and not args.force:
            for title, items in problems:
                print(title)
                for item in items[:20]:
                    print("  " + item)
            print("refusing to grow the baseline (use --force)")
            return 1
        with open(args.baseline, "w") as handle:
            json.dump(snapshot(result), handle, indent=1, sort_keys=True)
            handle.write("\n")
        summary(result)
        return 0
    summary(result)
    for title, items in problems:
        print(f"FAIL {title}: {len(items)}")
        for item in items[:30]:
            print("  " + item)
    shrunk = [k for k in LISTS if set(base.get(k, [])) - set(result[k])]
    shrunk += [k for k in COUNTS if result[k] < base.get(k, 0)]
    if shrunk and not problems:
        print("ratchet can tighten: " + " ".join(shrunk) + " (python3 tools/layers/layers.py update)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
