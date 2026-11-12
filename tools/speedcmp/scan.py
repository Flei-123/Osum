import collections
import sys

from report import load_symbols, resolver

INTERESTING_LEAVES = {"machine__in8", "machine__out8", "regio__read32_at", "regio__write32_at"}


def main():
    path, elf, top, start, end, leaf_filter = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
    symbols = load_symbols(elf)
    text_lo = min(a for a, _ in symbols)
    text_hi = max(a for a, _ in symbols)
    resolve = resolver(symbols)
    seen = collections.Counter()
    total = 0
    for line in open(path):
        parts = line.split()
        if len(parts) < 6 or not (start <= float(parts[0]) < end) or int(parts[2], 16) & 3:
            continue
        leaf = resolve(int(parts[3], 16))
        if leaf_filter != "*" and leaf_filter not in leaf:
            continue
        total += 1
        names = set()
        for word in parts[5].split(","):
            if word and text_lo <= int(word, 16) <= text_hi:
                names.add(resolve(int(word, 16)))
        for name in names:
            seen[name] += 1
    print("samples", total)
    for name, count in seen.most_common(top):
        print("%5d %5.1f%% %s" % (count, 100.0 * count / max(total, 1), name))


if __name__ == "__main__":
    main()
