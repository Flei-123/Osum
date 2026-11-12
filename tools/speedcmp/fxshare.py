import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from smcore import HEADER, TARGET, read_tsv
from stacks import load_symbols, resolver

ENTRY_FRAMES = ("sys__dispatch", "sys__entry", "sys__entry_quick")
TOP = 10


def load_map(path):
    return [(r["pattern"], r["test"]) for r in read_tsv(path)]


def handler_histogram(samples_path, elf, t0):
    raw_resolve = resolver(load_symbols(elf))
    resolve = lambda addr: re.sub(r"^_F\d+\.", "", raw_resolve(addr))
    hist, total = collections.Counter(), 0
    for line in open(samples_path):
        parts = line.split()
        if len(parts) < 3 or float(parts[0]) < t0:
            continue
        total += 1
        if int(parts[1], 16) & 3:
            continue
        frames = [resolve(int(parts[2], 16))] + ([resolve(int(x, 16)) for x in parts[3].split(",")] if len(parts) > 3 else [])
        idx = next((i for i, f in enumerate(frames) if f in ENTRY_FRAMES), -1)
        if idx > 0:
            hist[frames[idx - 1]] += 1
    return hist, total


def read_histogram(path):
    hist, total = collections.Counter(), 0
    for line in open(path):
        parts = line.split("\t")
        if len(parts) == 2 and parts[1].strip().isdigit():
            if parts[0] == "TOTAL":
                total = int(parts[1])
            else:
                hist[parts[0]] += int(parts[1])
    return hist, total


def share_by_test(hist, total, mapping):
    shares = collections.Counter()
    for handler, count in hist.items():
        test = next((t for pattern, t in mapping if pattern in handler), None)
        if test:
            shares[test] += count / max(total, 1)
    return shares


def rank(shares, matrix):
    ratios = {r["test"]: float(r["ratio"]) for r in matrix if r["ratio"]}
    rows = []
    for test, share in shares.items():
        ratio = ratios.get(test)
        if ratio is None or ratio <= TARGET:
            continue
        rows.append((share * (1.0 - TARGET / ratio), test, ratio, share))
    return sorted(rows, reverse=True)[:TOP]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", default="docs/speed-osum-vs-linux.tsv")
    parser.add_argument("--map", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "fxmap.tsv"))
    parser.add_argument("--hist")
    parser.add_argument("--samples")
    parser.add_argument("--elf")
    parser.add_argument("--t0", type=float, default=0.0)
    args = parser.parse_args()
    if args.hist:
        hist, total = read_histogram(args.hist)
    elif args.samples and args.elf:
        hist, total = handler_histogram(args.samples, args.elf, args.t0)
    else:
        parser.error("need --hist or --samples with --elf")
    matrix = read_tsv(args.matrix)
    print("%-28s %8s %8s %12s" % ("test", "ratio", "share%", "saving_if_1.0%"))
    for saving, test, ratio, share in rank(share_by_test(hist, total, load_map(args.map)), matrix):
        print("%-28s %8.2f %8.2f %12.2f" % (test, ratio, 100 * share, 100 * saving))


main()
