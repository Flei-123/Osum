import argparse
import os
import re
import sys

FN_RE = re.compile(r"^(?:export\s+)?fn\s+(\w+)\s*\(")
DEREF_RE = re.compile(r"\*\(|as \*(?:mut|const)\b")
CALL_RE = re.compile(r"(?<![\w.])(\w+)\s*\(")
USE_RE = re.compile(r"\b(\w+)\.(\w+)\s*\(")
VOLATILE_RE = re.compile(r"__mmio_|\bread8\(|\bget8\(|\bread8_at\b|\bwrite8_at\b|\bregio\.|\bkstate\.(?:get|set)")
RISK_DIRS = ("kernel/drv", "kernel/acpi", "kernel/bus")
VOLATILE_FUNCS = {
    "kernel/lib/kstate.fi": ["get8", "set8", "get", "set"],
}
ALL_VOLATILE_FILES = ["lib/libc/regio.fi"]
UNMASKED_NARROWING_RE = re.compile(r"\bv as u(?:8|16|32)\b")


def parse(path):
    funcs = {}
    name = None
    buf = []
    with open(path, errors="replace") as handle:
        for line in handle:
            m = FN_RE.match(line)
            if m:
                name = m.group(1)
                buf = [line]
            elif name:
                buf.append(line)
                if line.startswith("}"):
                    funcs[name] = "".join(buf)
                    name = None
    return funcs


def memory_functions(root):
    result = set()
    libc = os.path.join(root, "lib/libc")
    if not os.path.isdir(libc):
        return result
    for fname in sorted(os.listdir(libc)):
        if not fname.endswith(".fi") or fname == "regio.fi":
            continue
        module = fname[:-3]
        funcs = parse(os.path.join(libc, fname))
        mem = {n for n, b in funcs.items() if DEREF_RE.search(b)}
        changed = True
        while changed:
            changed = False
            for n, b in funcs.items():
                if n not in mem and any(c in mem for c in CALL_RE.findall(b)):
                    mem.add(n)
                    changed = True
        result.update((module, n) for n in mem)
    return result


def read_whitelist(root):
    path = os.path.join(root, "tools/mmio/plain-ok.txt")
    entries = {}
    if os.path.exists(path):
        for line in open(path):
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t", 1)
            entries[parts[0]] = parts[1].strip() if len(parts) > 1 else ""
    return entries


def risk_files(root):
    for base in RISK_DIRS:
        for dirpath, _, names in os.walk(os.path.join(root, base)):
            for n in sorted(names):
                if n.endswith(".fi"):
                    yield os.path.relpath(os.path.join(dirpath, n), root)


def check_imports(root, problems):
    memory = memory_functions(root)
    white = read_whitelist(root)
    used_white = set()
    for rel in risk_files(root):
        text = open(os.path.join(root, rel), errors="replace").read()
        hits = sorted({f"{m}.{f}" for m, f in USE_RE.findall(text) if (m, f) in memory})
        if not hits:
            continue
        if rel in white and white[rel]:
            used_white.add(rel)
        else:
            problems.append(f"plain memory access without plain-ok entry: {rel}: {', '.join(hits)}")
    for rel, reason in white.items():
        if not os.path.exists(os.path.join(root, rel)):
            problems.append(f"plain-ok entry for missing file: {rel}")
        elif not reason:
            problems.append(f"plain-ok entry without reason: {rel}")
        elif rel not in used_white:
            problems.append(f"stale plain-ok entry (no plain access left): {rel}")


def is_volatile(body):
    return bool(VOLATILE_RE.search(body.split("\n", 1)[1]))


def check_wrappers(root, problems):
    for rel, names in VOLATILE_FUNCS.items():
        path = os.path.join(root, rel)
        funcs = parse(path) if os.path.exists(path) else {}
        for n in names:
            if n not in funcs or not is_volatile(funcs[n]):
                problems.append(f"volatile wrapper inlined to plain or missing: {rel}:{n}")
    for rel in ALL_VOLATILE_FILES:
        path = os.path.join(root, rel)
        funcs = parse(path) if os.path.exists(path) else {}
        if not funcs:
            problems.append(f"volatile module missing: {rel}")
        for n, body in funcs.items():
            if not is_volatile(body):
                problems.append(f"volatile wrapper inlined to plain: {rel}:{n}")
            if UNMASKED_NARROWING_RE.search(body):
                problems.append(f"unmasked narrowing of write value: {rel}:{n}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    args = ap.parse_args()
    problems = []
    check_imports(args.root, problems)
    check_wrappers(args.root, problems)
    for p in problems:
        print("FAIL " + p)
    if not problems:
        print("mmio check clean")
    return 1 if problems else 0


sys.exit(main())
