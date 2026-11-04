#!/usr/bin/env python3
import csv
import fnmatch
import os
import subprocess
import sys

MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gates.tsv")
ROOTS = ("lib/", "kernel/")
MIN_LITERAL_SEGMENTS = 2


def literal_segments(pattern):
    if not any(ch in pattern for ch in "*?["):
        return MIN_LITERAL_SEGMENTS
    count = 0
    for part in pattern.split("/")[:-1]:
        if any(ch in part for ch in "*?["):
            break
        count += 1
    return count


def load_patterns():
    patterns = []
    with open(MANIFEST, newline="") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            for pattern in row["paths"].split(","):
                pattern = pattern.strip()
                if pattern and literal_segments(pattern) >= MIN_LITERAL_SEGMENTS and pattern.startswith(ROOTS):
                    patterns.append((row["gate"], pattern))
    return patterns


def unit_of(path):
    parts = path.split("/")
    return "/".join(parts[:2]) if len(parts) > 2 else path


def uncovered(root):
    tracked = subprocess.check_output(["git", "ls-files", "lib", "kernel"], cwd=root, text=True).split("\n")
    patterns = load_patterns()
    missing = {}
    for path in tracked:
        if not path.endswith(".fi") or not path.startswith(ROOTS):
            continue
        if not any(fnmatch.fnmatch(path, pattern) for _, pattern in patterns):
            missing.setdefault(unit_of(path), []).append(path)
    return missing


def main(argv):
    root = os.getcwd()
    missing = uncovered(root)
    for unit in sorted(missing):
        print(f"{unit}\t{len(missing[unit])} files without a gate path")
    print(f"units without gate path: {len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
