#!/usr/bin/env python3
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import shapechrome

WIN = re.compile(r"settings: rect name=win x=(\d+) y=(\d+) w=\d+ h=\d+ ax=(\d+) ay=(\d+)")
SEARCH = re.compile(r"settings: rect name=waa x=(\d+) y=(\d+) w=\d+ h=\d+ ax=(\d+) ay=(\d+)")


def main(serial_path, scale, out_dir):
    text = open(serial_path, "rb").read().decode("latin1")
    wins = WIN.findall(text)
    searches = SEARCH.findall(text)
    if not wins or not searches:
        print("wininset=missing win_records=%d search_records=%d" % (len(wins), len(searches)))
        return 1
    x, y, ax, ay = (int(v) for v in wins[-1])
    sx, sy, sax, say = (int(v) for v in searches[-1])
    inset_x, inset_y = shapechrome.client_inset(out_dir)
    want = (inset_x * scale, inset_y * scale)
    got = (ax - x, ay - y)
    inset_ok = got == want
    chain_ok = (sax, say) == (ax + sx, ay + sy)
    print("wininset=%s chain=%s inset=%d/%d want=%d/%d search=%d/%d window_client=%d/%d"
          % ("ok" if inset_ok else "wrong", "ok" if chain_ok else "wrong",
             got[0], got[1], want[0], want[1], sax, say, ax, ay))
    return 0 if inset_ok and chain_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], int(sys.argv[2]), sys.argv[3]))
