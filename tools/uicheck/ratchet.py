#!/usr/bin/env python3
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASELINE = os.path.join(ROOT, "tools", "uicheck", "draw_baseline.tsv")
PRIMITIVE = re.compile(
    rb"\b(?:painter\.(?:round_rect|round_ring|round_rect_grad|round_rect_radial|surface)"
    rb"|(?:fuiscene|fscore)\.cv_(?:rgb|rect|round|ring|round_rgb|ring_rgb|round_a|ring_a|round_raw|ring_raw)"
    rb"|wlibc\.(?:rect|frame|frame3|hline|vline|plate)"
    rb"|fuib\.(?:rect|rrect|ring|rring|frame|rframe|board|area|hline|dot)"
    rb"|wlib\.draw_(?:board|area|bar|frame|edge3|line|point))\s*\(")
COMPONENT_DIRS = ("kernel/user/uikit/", "kernel/user/fuiscene/", "kernel/user/fuiapp/", "kernel/user/wlibc/", "kernel/user/wlib/")
COMPONENT_FILES = {"kernel/user/fuiscene.fi", "kernel/user/wlibc.fi", "kernel/user/wlib.fi",
                   "kernel/user/fuib.fi", "kernel/user/fuiapp.fi"}


def is_component(rel):
    return rel in COMPONENT_FILES or rel.startswith(COMPONENT_DIRS)


def tracked_sources(root):
    out = subprocess.run(["git", "ls-files", "kernel/user"], cwd=root, capture_output=True, check=True).stdout
    for line in out.decode().splitlines():
        if line.endswith(".fi") and not is_component(line):
            yield line


def count_text(data):
    return len(PRIMITIVE.findall(data))


def count(root):
    counts = {}
    for rel in tracked_sources(root):
        path = os.path.join(root, rel)
        if not os.path.exists(path):
            continue
        n = count_text(open(path, "rb").read())
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
        f.write("# file\traw draw calls outside the UI components (may only shrink, docs/ui-system.md)\n")
        for rel in sorted(counts):
            f.write("%s\t%d\n" % (rel, counts[rel]))


def compare(counts, base):
    bad = 0
    for rel, n in sorted(counts.items()):
        allowed = base.get(rel, 0)
        if n > allowed:
            print("RATCHET %s: %d raw draw calls, allowed %d (use kernel/user/uikit or fuiscene)" % (rel, n, allowed))
            bad += 1
        elif n < allowed:
            print("SHRUNK  %s: %d < baseline %d (run update)" % (rel, n, allowed))
            bad += 1
    for rel in sorted(set(base) - set(counts)):
        print("SHRUNK  %s: 0 < baseline %d (run update)" % (rel, base[rel]))
        bad += 1
    return bad


def update(counts):
    if os.path.exists(BASELINE):
        old = read_baseline(BASELINE)
        for rel, n in counts.items():
            if n > old.get(rel, 0):
                sys.exit("refusing to grow baseline: %s" % rel)
    write_baseline(BASELINE, counts)
    print("baseline: %d files, %d raw draw calls" % (len(counts), sum(counts.values())))


def selftest(counts, base):
    probe = dict(counts)
    victim = sorted(counts)[0]
    probe[victim] += 1
    grown = compare(probe, base)
    sample = b"painter.round_rect(z, 0.0, 0.0, 1.0, 1.0, 0.0, c)\nfuiscene.cv_round_rgb(x, y)\nuisurface.paint(k, 0, 0, 1, 1)\n"
    found = count_text(sample)
    print("selftest: grown file flagged %s, sample count %d (want 2)" % (grown > 0, found))
    return 0 if grown > 0 and found == 2 else 1


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    counts = count(ROOT)
    if mode == "update":
        update(counts)
        return
    base = read_baseline(BASELINE)
    if mode == "selftest":
        sys.exit(selftest(counts, base))
    bad = compare(counts, base)
    print("uicheck ratchet: %d files, %d raw draw calls, %s" % (len(counts), sum(counts.values()),
                                                                 "ok" if bad == 0 else "%d problems" % bad))
    sys.exit(1 if bad else 0)


main()
