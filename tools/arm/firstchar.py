#!/usr/bin/env python3
"""tools/arm/firstchar.py -- how long until the machine says anything.

    ./tools/arm/firstchar.py <image.elf> [repeats]

Starts `qemu-system-aarch64 -M virt` and reports the wall clock time from
the moment the process is spawned to the moment the FIRST octet arrives on
the PL011, in milliseconds, plus the total time to the last line.

Why measure this at all: on the x86 side "it boots" is proved by a serial
line appearing, and how long that takes is never asked. On a new port it is
the only number available before anything else works, and it is the number
that will move when the kernel proper is hoisted onto this side -- so it is
worth having a starting value that was taken and not remembered.

What it does NOT measure: the time QEMU itself needs to start, which is in
there and is the larger part. The figure is therefore an upper bound on the
kernel's own start, and it is reported as such.
"""
import subprocess
import sys
import time

QEMU = ["qemu-system-aarch64", "-M", "virt", "-cpu", "cortex-a53",
        "-m", "128", "-nographic", "-kernel"]


def one(image):
    t0 = time.monotonic()
    p = subprocess.Popen(QEMU + [image], stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    first = None
    data = b""
    while True:
        c = p.stdout.read(1)
        if not c:
            break
        if first is None:
            first = time.monotonic()
        data += c
        if data.endswith(b"osum-arm: done\n"):
            break
    last = time.monotonic()
    p.kill()
    p.wait()
    if first is None:
        return None, None, data
    return (first - t0) * 1000.0, (last - t0) * 1000.0, data


def main():
    image = sys.argv[1]
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    firsts, totals = [], []
    for _ in range(n):
        f, t, _ = one(image)
        if f is None:
            print("no output at all")
            raise SystemExit(1)
        firsts.append(f)
        totals.append(t)
    firsts.sort()
    totals.sort()
    print("first octet on the PL011: %.1f ms (median of %d, %.1f..%.1f)"
          % (firsts[len(firsts) // 2], n, firsts[0], firsts[-1]))
    print("to the last line:         %.1f ms (median of %d, %.1f..%.1f)"
          % (totals[len(totals) // 2], n, totals[0], totals[-1]))


if __name__ == "__main__":
    main()
