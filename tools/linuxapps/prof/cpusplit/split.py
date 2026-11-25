import re
import statistics
import sys

WINDOWS = {"load": ("begin", "png"), "exit": ("png", "rc")}
USER_HZ = 100.0


def parse(path):
    runs = {}
    pattern = re.compile(r"FXSTAT (\d+) (\w+) user=(\d+) sys=(\d+) idle=(\d+)")
    for line in open(path, errors="replace"):
        m = pattern.search(line)
        if m:
            runs.setdefault(int(m.group(1)), {})[m.group(2)] = tuple(map(int, m.group(3, 4, 5)))
    return runs


def main():
    runs = parse(sys.argv[1])
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    warm = [n for n in sorted(runs) if n >= first and len(runs[n]) == 3]
    if not warm:
        sys.exit("cpusplit: no complete warm runs")
    for name, (a, b) in WINDOWS.items():
        cols = [statistics.median((runs[n][b][k] - runs[n][a][k]) / USER_HZ for n in warm) for k in range(3)]
        print("%s runs=%d user=%.2f sys=%.2f idle=%.2f s" % (name, len(warm), cols[0], cols[1], cols[2]))


main()
