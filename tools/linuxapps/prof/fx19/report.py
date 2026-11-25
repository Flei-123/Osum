import collections
import re
import sys

WINDOWS = (("begin", "png"), ("png", "rc"))
LINE = re.compile(r"FX19 (\d+) (begin|png|rc) (\S+)\s+(\d+)")


def load(path):
    snaps = collections.defaultdict(dict)
    for line in open(path, errors="ignore"):
        match = LINE.match(line.strip())
        if match:
            snaps[(int(match[1]), match[2])][match[3]] = int(match[4])
    return snaps


def window_deltas(snaps, start, end, prefixes):
    runs = sorted({run for run, _ in snaps})
    keys = sorted({key for snap in snaps.values() for key in snap})
    rows = {}
    for key in keys:
        if prefixes and not key.startswith(prefixes):
            continue
        row = [snaps[(r, end)][key] - snaps[(r, start)][key]
               for r in runs if key in snaps.get((r, start), {}) and key in snaps.get((r, end), {})]
        if any(row):
            rows[key] = row
    return rows


def main():
    snaps = load(sys.argv[1])
    prefixes = tuple(sys.argv[2:])
    for start, end in WINDOWS:
        print("== window %s -> %s" % (start, end))
        for key, row in window_deltas(snaps, start, end, prefixes).items():
            print("%-28s %s" % (key, " ".join("%12d" % value for value in row)))


if __name__ == "__main__":
    main()
