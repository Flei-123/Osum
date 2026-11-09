#!/usr/bin/env python3
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASELINE = os.path.join(ROOT, "tools", "palette", "hex_baseline.tsv")
LITERAL = re.compile(rb"(?<![&] )(?<!&)0x(?:00|FF|ff)?[0-9A-Fa-f]{6}\b")
ALPHA_MASK = re.compile(rb"0x[Ff]{6}[0-9A-Fa-f]{2}$")
SKIP = {"kernel/user/uitheme/thdark.fi"}


def tracked_sources(root):
    out = subprocess.run(["git", "ls-files", "kernel/user"], cwd=root, capture_output=True, check=True).stdout
    for line in out.decode().splitlines():
        if line.endswith(".fi") and line not in SKIP:
            yield line


def count(root):
    counts = {}
    for rel in tracked_sources(root):
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            continue
        n = sum(1 for m in LITERAL.findall(open(path, "rb").read()) if not ALPHA_MASK.match(m))
        if n:
            counts[rel] = n
    return counts


def read_baseline(path):
    base = {}
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line and not line.startswith("#"):
            rel, n = line.split("\t")
            base[rel] = int(n)
    return base


def write_baseline(path, counts):
    with open(path, "w", encoding="utf-8") as f:
        f.write("# file\tcolor-literal count (may only shrink)\n")
        for rel in sorted(counts):
            f.write("%s\t%d\n" % (rel, counts[rel]))


def compare(counts, base):
    bad = 0
    for rel, n in sorted(counts.items()):
        allowed = base.get(rel, 0)
        if n > allowed:
            print("RATCHET %s: %d literals, allowed %d" % (rel, n, allowed))
            bad += 1
        elif n < allowed:
            print("SHRUNK  %s: %d < baseline %d (run update)" % (rel, n, allowed))
            bad += 1
    for rel in sorted(set(base) - set(counts)):
        print("SHRUNK  %s: 0 < baseline %d (run update)" % (rel, base[rel]))
        bad += 1
    return bad


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    counts = count(ROOT)
    if mode == "update":
        if os.path.exists(BASELINE):
            old = read_baseline(BASELINE)
            for rel, n in counts.items():
                if n > old.get(rel, 0):
                    sys.exit("refusing to grow baseline: %s" % rel)
        write_baseline(BASELINE, counts)
        print("baseline: %d files, %d literals" % (len(counts), sum(counts.values())))
        return
    if mode == "selftest":
        probe = dict(counts)
        victim = sorted(counts)[0]
        probe[victim] += 1
        fresh = dict(counts)
        fresh["kernel/user/zz_new_file.fi"] = 1
        red1 = compare(probe, read_baseline(BASELINE))
        red2 = compare(fresh, read_baseline(BASELINE))
        ok = red1 > 0 and red2 > 0
        print("ratchet selftest: %s" % ("OK" if ok else "FAIL"))
        sys.exit(0 if ok else 1)
    bad = compare(counts, read_baseline(BASELINE))
    print("ratchet: %s (%d literals in %d files)" % ("FAIL" if bad else "OK", sum(counts.values()), len(counts)))
    sys.exit(1 if bad else 0)


main()
