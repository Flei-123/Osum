import collections
import sys

from report import load_symbols, resolver


def main():
    path, elf, top, start, depth = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5])
    resolve = resolver(load_symbols(elf))
    stacks = collections.Counter()
    total = 0
    for line in open(path):
        parts = line.split()
        if len(parts) < 4 or float(parts[0]) < start or int(parts[2], 16) & 3:
            continue
        total += 1
        frames = [resolve(int(parts[3], 16))]
        if len(parts) > 4:
            frames += [resolve(int(x, 16)) for x in parts[4].split(",") if x != "-"]
        stacks[" < ".join(frames[:depth])] += 1
    print("samples", total)
    for stack, count in stacks.most_common(top):
        print("%5d %5.1f%% %s" % (count, 100.0 * count / max(total, 1), stack))


if __name__ == "__main__":
    main()
