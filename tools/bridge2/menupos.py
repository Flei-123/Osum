#!/usr/bin/env python3
import re
import sys

GEOM = re.compile(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
LIST = re.compile(r"launcher: rect id=2 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
ROWS = re.compile(r"launcher: rows x=\d+ base=\d+ zh=(\d+)")
HIT = r"launcher: treffer i=(\d+) name=\[[^\]]*\] exec=\[%s\]"


def locate(serial, exec_path):
    geoms = GEOM.findall(serial)
    lists = LIST.findall(serial)
    rows = ROWS.findall(serial)
    hits = re.findall(HIT % re.escape(exec_path), serial)
    if not (geoms and lists and rows and hits):
        return None
    gx, gy = int(geoms[-1][0]), int(geoms[-1][1])
    lx, ly, lw, lh = (int(v) for v in lists[-1])
    row_h = int(rows[-1])
    index = int(hits[-1])
    return gx + lx + lw // 2, gy + ly + index * row_h + row_h // 2


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin1")
    pos = locate(serial, sys.argv[2])
    if pos is None:
        sys.exit(1)
    print("%d,%d" % pos)


if __name__ == "__main__":
    main()
