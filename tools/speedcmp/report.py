import bisect
import collections
import subprocess
import sys


def load_symbols(elf):
    symbols = []
    output = subprocess.run(["nm", "-n", elf], capture_output=True, text=True).stdout
    for line in output.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tTwW":
            symbols.append((int(parts[0], 16), parts[2]))
    return symbols


def resolver(symbols):
    addresses = [a for a, _ in symbols]

    def resolve(addr):
        i = bisect.bisect_right(addresses, addr) - 1
        return symbols[i][1].replace("_F1.", "") if i >= 0 else "?"

    return resolve


def main():
    path, elf, top, start, cpu = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5])
    resolve = resolver(load_symbols(elf))
    inclusive = collections.Counter()
    leaf = collections.Counter()
    total = user = 0
    for line in open(path):
        parts = line.split()
        if len(parts) < 4 or float(parts[0]) < start or int(parts[1]) != cpu:
            continue
        if int(parts[2], 16) & 3:
            user += 1
            continue
        total += 1
        frames = [resolve(int(parts[3], 16))]
        if len(parts) > 4:
            frames += [resolve(int(x, 16)) for x in parts[4].split(",")]
        leaf[frames[0]] += 1
        for name in set(frames):
            inclusive[name] += 1
    print("cpu", cpu, "kernel", total, "user", user)
    print("-- inclusive")
    for name, count in inclusive.most_common(top):
        print("%5d %5.1f%% %s" % (count, 100.0 * count / max(total, 1), name))
    print("-- leaf")
    for name, count in leaf.most_common(top):
        print("%5d %5.1f%% %s" % (count, 100.0 * count / max(total, 1), name))


if __name__ == "__main__":
    main()
