import glob
import statistics
import sys


def load(directory):
    values = {}
    for path in sorted(glob.glob(directory + "/osum-*.txt")):
        for line in open(path, errors="replace"):
            parts = line.split()
            if len(parts) >= 4 and parts[0] == "S" and parts[1] not in ("END", "BEGIN"):
                try:
                    values.setdefault(parts[1], []).append(float(parts[2]))
                except ValueError:
                    pass
    return values


def main():
    base = load(sys.argv[1])
    new = load(sys.argv[2])
    for name in sorted(set(base) | set(new)):
        a = base.get(name, [])
        b = new.get(name, [])
        ma = statistics.median(a) if a else float("nan")
        mb = statistics.median(b) if b else float("nan")
        print("%-28s base %14.1f (%d)  new %14.1f (%d)  new/base %.3f" % (name, ma, len(a), mb, len(b), mb / ma if a and b else float("nan")))


main()
