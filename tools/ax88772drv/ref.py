# SPDX-License-Identifier: GPL-2.0-only
# Expected serial lines of tools/ax88772drv/test.fi, computed from the Asix protocol description only.
import sys

PAUSE = 150000
SEQ = [(0x40, 0x22, 1, 0), (0x40, 0x20, 0x48, 0), (0x40, 0x20, 0x00, 0), (0x40, 0x20, 0x20, 0),
       (0x40, 0x10, 0, 0), (0xC0, 0x13, 0, 6), (0x40, 0x1B, 0x336, 0), (0x40, 0x10, 0x88, 0)]
MAC = [0x02 + i * 0x11 for i in range(6)]


def frame(n):
    return bytes(((i * 7 + 3) & 255) for i in range(n))


def wsum(b):
    return sum(v * (i + 1) for i, v in enumerate(b)) & 65535


def expected(skip=None):
    out = []
    for k, (bm, req, val, ln) in enumerate(SEQ):
        out.append(f"ax: ctl {bm} {req} {val} 0 {ln}")
        if req == 0x20:
            out.append(f"ax: pause {PAUSE}")
    out.append("ax: step 0 mac " + " ".join(str(v) for v in MAC))
    out.append("ax: rxctl 136 medium 822")
    sizes = [60, 100, 1514, 61]
    for n in sizes:
        out.append(f"ax: rx {n} {wsum(frame(n))}")
    out.append(f"ax: rx frames {len(sizes)}")
    for n in (60, 508, 1514, 1020):
        total = 4 + n
        pad = 0
        if total % 512 == 0:
            pad = 0xFFFF0000
            total += 4
        out.append(f"ax: tx {n} total {total} pad {pad} sum {wsum(frame(n))} ok 1")
    return out


if __name__ == "__main__":
    print("\n".join(expected()))
