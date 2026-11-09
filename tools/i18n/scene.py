#!/usr/bin/env python3
import re
import sys

TEXT = re.compile(
    r"^(wlib|taskbar): text (?:win=\d+ kind=(\d+) )?(?:(\w+) )?"
    r"x=(-?\d+) base=(-?\d+) fg=(\d+) bg=(\d+)(?: tw=(\d+))?"
    r"(?: ax=(-?\d+) ay=(-?\d+))?(?: ow=\d+ bw=\d+)? t=(.*)$")

TASKBAR_Y = 770


def latest(path, text, source):
    batch = []
    for raw in open(path, "rb").read().decode("utf-8", "replace").splitlines():
        line = raw.strip()
        if source == "wlib" and line.startswith("wlib: texts "):
            batch = []
            continue
        m = TEXT.match(line)
        if m and m.group(1) == source and m.group(11) == text:
            batch.append(m)
    if not batch:
        return None
    if source != "wlib":
        return batch[-1]
    painted = [m for m in batch if m.group(2) == "1"]
    return painted[0] if painted else batch[0]


def find(path, text, source="wlib"):
    m = latest(path, text, source)
    if m is None:
        return None
    x, base = int(m.group(4)), int(m.group(5))
    if source == "wlib":
        x += int(m.group(9) or 0)
        base += int(m.group(10) or 0)
    else:
        base += TASKBAR_Y
    return x, base, int(m.group(8) or 0), int(m.group(6)), int(m.group(7))


def rgb(value):
    return (value >> 16) & 255, (value >> 8) & 255, value & 255


def read_ppm(path):
    raw = open(path, "rb").read()
    fields = []
    i = 2
    while len(fields) < 3:
        while raw[i:i + 1].isspace():
            i += 1
        j = i
        while not raw[j:j + 1].isspace():
            j += 1
        fields.append(int(raw[i:j]))
        i = j
    return fields[0], fields[1], raw[i + 1:]


def cmd_find(a):
    r = find(a[0], a[1], a[2] if len(a) > 2 else "wlib")
    if r is None:
        return 1
    print("%d %d %d" % r[:3])
    return 0


def cmd_colors(a):
    r = find(a[0], a[1], a[2] if len(a) > 2 else "wlib")
    if r is None:
        return 1
    print("%d %d %d" % rgb(r[3]))
    return 0


def cmd_ground(a):
    w, h, d = read_ppm(a[0])
    x, y = int(a[1]) - 3, int(a[2]) - 5
    o = (y * w + x) * 3
    print("%d %d %d" % (d[o], d[o + 1], d[o + 2]))
    return 0


def cmd_ink(a):
    w, h, d = read_ppm(a[0])
    x0, y0, tw = int(a[1]), int(a[2]), int(a[3])
    o = ((y0 - 5) * w + (x0 - 3)) * 3
    ground = (d[o], d[o + 1], d[o + 2])
    count = 0
    for y in range(y0 - 14, y0 + 6):
        for x in range(x0 - 4, x0 + tw + 8):
            o = (y * w + x) * 3
            delta = (abs(d[o] - ground[0]) + abs(d[o + 1] - ground[1])
                     + abs(d[o + 2] - ground[2]))
            if delta > 150:
                count += 1
    print(count)
    return 0 if count >= 15 else 1


def main():
    cmds = {"find": cmd_find, "colors": cmd_colors, "ground": cmd_ground,
            "ink": cmd_ink}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print("usage: scene.py find|colors <serial> <text> [wlib|taskbar] | ground <ppm> <x> <base> | ink <ppm> <x> <base> <tw>")
        return 2
    return cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
