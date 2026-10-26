#!/usr/bin/env python3
import argparse
import bisect
import subprocess
import sys

USAGE = """Resolve the allocation sites of /proc/<pid>/mmaplog to function+offset and flag leaks.

Get the matching symbol ELF for an image build directory OUT (the directory build.sh wrote, same commit as the image):
  bash tools/taskbarmem/symelf.sh OUT taskbar OUT/taskbar.sym.elf
(build.sh strips OUT/taskbar.elf; the script relinks OUT/taskbar.o unstripped and checks that .text is identical.)

Collect the log on the machine:  /bin/cat /proc/<taskbar-pid>/mmaplog   (pid from /bin/ps)

Run:  python3 tools/taskbarmem/analyze.py mmaplog.txt --elf OUT/taskbar.sym.elf
A row is flagged LEAK when it maps at least --min-count times and fewer than half of that many bytes are given back by
unmap rows of the same length. Text base is 0x40100000; stack-growth faults show up as 4096-byte maps inside a function body.
"""


def load_symbols(elf):
    out = subprocess.run(["nm", "-n", elf], capture_output=True, text=True, check=True).stdout
    syms = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1] in "tTwW":
            syms.append((int(parts[0], 16), parts[2]))
    return [a for a, _ in syms], syms


def resolve(addrs, syms, value):
    if not addrs or value < addrs[0]:
        return "?"
    i = bisect.bisect_right(addrs, value) - 1
    return "%s+0x%x" % (syms[i][1], value - syms[i][0])


def parse(text):
    rows = []
    lost = 0
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 6 and parts[0] in ("m", "u"):
            rows.append((parts[0], int(parts[1]), int(parts[2], 16), int(parts[3], 16), int(parts[4], 16), int(parts[5])))
        elif len(parts) == 2 and parts[0] == "lost:":
            lost = int(parts[1])
    return rows, lost


def analyze(rows, min_count):
    unmapped = {}
    for kind, length, _, _, _, count in rows:
        if kind == "u":
            unmapped[length] = unmapped.get(length, 0) + count
    result = []
    for kind, length, rip, c1, c2, count in rows:
        if kind != "m":
            continue
        back = unmapped.get(length, 0)
        leak = count >= min_count and back * 2 < count
        result.append((count * length, count, length, back, leak, rip, c1, c2))
    result.sort(reverse=True)
    return result


def selftest():
    text = "kind len rip caller1 caller2 count\nm 65536 40195159 401a6f89 40166d09 500\nm 4096 4010c3ca 4010c943 4010ca46 16\nm 262144 4013dcd3 4013de78 4013dde6 40\nu 262144 4013dd59 4013e197 4013dde6 40\nlost: 0\n"
    rows, lost = parse(text)
    res = analyze(rows, 20)
    flags = {r[2]: r[4] for r in res}
    assert flags[65536] is True
    assert flags[4096] is False
    assert flags[262144] is False
    assert lost == 0
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser(description=USAGE, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", nargs="?", default="-")
    ap.add_argument("--elf")
    ap.add_argument("--top", type=int, default=15)
    ap.add_argument("--min-count", type=int, default=20)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--fail-on-leak", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return 0
    text = sys.stdin.read() if args.log == "-" else open(args.log).read()
    rows, lost = parse(text)
    if not rows:
        print("no rows")
        return 2
    addrs, syms = ([], [])
    if args.elf:
        addrs, syms = load_symbols(args.elf)

    def name(v):
        return resolve(addrs, syms, v) if addrs else "%08x" % v

    result = analyze(rows, args.min_count)
    leaks = 0
    print("lost rows: %d" % lost)
    for total, count, length, back, leak, rip, c1, c2 in result[: args.top]:
        flag = "LEAK" if leak else "ok  "
        leaks += 1 if leak else 0
        print("%s %9d B  x%-6d len=%-8d unmaps=%-6d rip=%s c1=%s c2=%s" % (flag, total, count, length, back, name(rip), name(c1), name(c2)))
    print("leak rows in top %d: %d" % (args.top, leaks))
    return 1 if (args.fail_on_leak and leaks) else 0


if __name__ == "__main__":
    sys.exit(main())
