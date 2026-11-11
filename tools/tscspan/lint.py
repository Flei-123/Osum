import os
import re
import subprocess
import sys

SKIP_PREFIXES = ("kernel/user/", "kernel/uprog/")
TSC_ASSIGN = re.compile(r"(\w+)\s*(?::\s*u64)?\s*=\s*\(?\s*(?:\w+\.)*(?:tsc|rdtsc)\(\)")
DIRECT = re.compile(r"(?:tsc|rdtsc)\(\)\s*-%?\s")


def source_files(root):
    listing = subprocess.check_output(["git", "-C", root, "ls-files", "kernel", "lib"], text=True)
    return [f for f in listing.split() if f.endswith(".fi") and not f.startswith(SKIP_PREFIXES)]


def scan_file(root, rel):
    with open(os.path.join(root, rel), "r", encoding="utf-8", errors="ignore") as handle:
        lines = handle.read().splitlines()
    names = {m.group(1) for line in lines for m in [TSC_ASSIGN.search(line)] if m}
    patterns = [re.compile(r"(?<![-%])-\s+" + re.escape(n) + r"\b") for n in names]
    hits = []
    for number, line in enumerate(lines, 1):
        if "since" in line or "expired" in line:
            continue
        if DIRECT.search(line) or any(p.search(line) for p in patterns):
            hits.append("%s:%d: %s" % (rel, number, line.strip()))
    return hits


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    baseline = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    hits = []
    for rel in source_files(root):
        hits.extend(scan_file(root, rel))
    for hit in hits:
        print(hit)
    print("%d raw tsc spans" % len(hits))
    return 1 if len(hits) > baseline else 0


sys.exit(main())
