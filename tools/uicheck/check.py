#!/usr/bin/env python3
import sys

KINDS = ["card", "flyout", "tip", "toast", "dialog", "chip"]
FILL = 0xF9F9F9
STROKE = 0xD6D6D6
BACK = 0
PLACES = {0: (8, 832), 1: (0, 0), 2: (1612, 832), 3: (770, 66), 4: (1, 0)}


def read_rows(path):
    rows = {}
    for line in open(path, encoding="ascii"):
        g, a, b, v = (int(t) for t in line.split())
        rows[(g, a, b)] = v
    return rows


def main():
    rows = read_rows(sys.argv[1])
    ok = bad = 0

    def claim(name, cond):
        nonlocal ok, bad
        print("%s  %s" % ("OK  " if cond else "FAIL", name))
        if cond:
            ok += 1
        else:
            bad += 1

    for k, name in enumerate(KINDS):
        for s in (1, 2):
            key = k * 10 + s
            tag = "%s scale %d" % (name, s)
            claim(tag + ": two contexts pixel-equal", rows.get((0, key, 0)) == 0)
            claim(tag + ": old look differs (counter-probe)", rows.get((0, key, 1), 0) > 0)
            claim(tag + ": corner is cut", rows.get((1, key, 0)) == BACK)
            claim(tag + ": body is fill role", rows.get((1, key, 1)) == FILL)
            claim(tag + ": edge is stroke role", rows.get((1, key, 2)) == STROKE)
            want_r = 8 * s if name != "chip" else 30 * s
            claim(tag + ": radius %d" % want_r, rows.get((1, key, 3)) == want_r)
    for case, (a, b) in PLACES.items():
        got = None
        for (g, c, x), v in rows.items():
            if g == 2 and c == case:
                got = (x, v)
        claim("flyout place case %d = %s" % (case, (a, b)), got == (a, b))
    print("uicheck pixels: %d ok, %d fail" % (ok, bad))
    sys.exit(1 if bad else 0)


main()
