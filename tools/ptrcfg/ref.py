#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Independent reference of the pointer curve (kernel/drv/hid/ptrcfg.fi).

Prints the expected `ptrcfg: case ...` and `ptrcfg: e2e ...` lines.
Written from the spec in the header of ptrcfg.fi, not from the Firn code.
"""
import sys

DENOM = 25600


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def gain(accel, mag):
    if accel == 0 or mag <= 1:
        return 256
    return 256 + accel * 8 * (min(mag, 32) - 1)


class Ptr:
    def __init__(self, speed, accel, nat):
        self.speed = clamp(speed, 10, 400)
        self.accel = clamp(accel, 0, 5)
        self.nat = 1 if nat else 0
        self.rem = [0, 0]

    def axis(self, v, mag, i):
        gn = gain(self.accel, mag)
        if self.speed == 100 and gn == 256:
            return v
        total = v * self.speed * gn + self.rem[i]
        q = abs(total) // DENOM
        out = -q if total < 0 else q
        self.rem[i] = total - out * DENOM
        return out

    def wheel(self, r):
        return -r if self.nat else r


def case(idx, sp, ac, nat):
    p = Ptr(sp, ac, nat)
    sx = sy = 0
    for i in range(24):
        dx = (i % 12) + 1
        dy = (i * 5) % 7
        if i % 3 == 1:
            dx = -dx
        if i % 4 == 2:
            dy = -dy
        mg = max(abs(dx), abs(dy))
        sx += p.axis(dx, mg, 0)
        sy += p.axis(dy, mg, 1)
    return "ptrcfg: case %d sp=%d ac=%d x=%d y=%d w=%d" % (
        idx, p.speed, p.accel, sx, sy, p.wheel(1))


CASES = [(100, 0, 0), (200, 0, 0), (50, 0, 0), (100, 2, 0), (150, 3, 1),
         (400, 5, 0), (10, 1, 1), (9999, 99, 0)]


def e2e():
    # speed 200, accel 0, natural; packet dx=+10, dy=+4 (up), wheel +1
    p = Ptr(200, 0, 1)
    mg = 10
    dx = p.axis(10, mg, 0)
    dy = p.axis(4, mg, 1)
    return "ptrcfg: e2e x=%d y=%d w=%d" % (100 + dx, 100 - dy, p.wheel(1))


if __name__ == "__main__":
    for i, (sp, ac, nat) in enumerate(CASES):
        print(case(i, sp, ac, nat))
    print(e2e())
