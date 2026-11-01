#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
