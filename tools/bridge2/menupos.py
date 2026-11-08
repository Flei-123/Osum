#!/usr/bin/env python3
import re
import sys

GEOM = re.compile(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
TILE = r"launcher: tile i=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)\s+name=\[%s\]"


def locate(serial, name):
    geoms = GEOM.findall(serial)
    tiles = re.findall(TILE % re.escape(name), serial)
    if not geoms or not tiles:
        return None
    gx, gy = int(geoms[-1][0]), int(geoms[-1][1])
    tx, ty, tw, th = (int(v) for v in tiles[-1])
    return gx + tx + tw // 2, gy + ty + th // 2


def main():
    serial = open(sys.argv[1], "rb").read().decode("latin1")
    pos = locate(serial, sys.argv[2])
    if pos is None:
        sys.exit(1)
    print("%d,%d" % pos)


if __name__ == "__main__":
    main()
