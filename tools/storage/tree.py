#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tree.py
"""

import os
import sys

FOLDER = ["messing", "kupfer", "zinn", "blei", "zink", "nickel",
          "chrom", "eisen"]


def names(n):
    aus = []
    for i in range(n):
        folder = FOLDER[i % len(FOLDER)]
        bottom = (i // len(FOLDER)) % 2 == 1
        path_2 = "/data/%s%s" % (folder, "/tief" if bottom else "")
        aus.append((path_2, "datei%04d.txt" % i))
    return aus


def groessen(n, budget):
    aus = [0] * n
    kand = list(range(0, n, 13))
    roh = []
    value = 65536
    for k in range(len(kand)):
        roh.append(value)
        if value > 64:
            value = value * 88 // 100
    sum_2 = sum(roh)
    for k, i in enumerate(kand):
        aus[i] = max(1, roh[k] * budget // sum_2)
    return aus


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    arbeit = argv[1]
    n = int(argv[2]) if len(argv) > 2 else 4000
    budget = int(argv[3]) if len(argv) > 3 else 600000
    inhalt = os.path.join(arbeit, "inhalt")
    os.makedirs(inhalt, exist_ok=True)

    list_2 = names(n)
    sz = groessen(n, budget)

    rows = ["--inodes=4096", "/data/"]
    seen = set()
    for path_2, _ in list_2:
        parts = path_2.strip("/").split("/")
        for k in range(1, len(parts) + 1):
            p = "/" + "/".join(parts[:k]) + "/"
            if p not in seen:
                seen.add(p)
                if p != "/data/":
                    rows.append(p)

    for i, (path_2, name) in enumerate(list_2):
        if sz[i] > 0:
            wirt = os.path.join(inhalt, "f%05d" % i)
            with open(wirt, "wb") as f:
                f.write(bytes([65 + (i % 26)]) * sz[i])
            rows.append("%s/%s=%s" % (path_2, name, wirt))
        else:
            rows.append("%s/%s=" % (path_2, name))

    with open(os.path.join(arbeit, "angaben"), "w") as f:
        f.write("\n".join(rows) + "\n")

    okt = {}
    kb = {}
    dat = {}

    def add_2(p, o):
        parts = p.strip("/").split("/")
        for k in range(0, len(parts) + 1):
            d = "/" + "/".join(parts[:k])
            if d == "":
                d = "/"
            if len(d) > 1 and d.endswith("/"):
                d = d[:-1]
            okt[d] = okt.get(d, 0) + o
            kb[d] = kb.get(d, 0) + (o + 1023) // 1024
            dat[d] = dat.get(d, 0) + 1

    for i, (path_2, _name) in enumerate(list_2):
        add_2(path_2, sz[i])
    for d in sorted(seen):
        dd = d if len(d) == 1 else d.rstrip("/")
        okt.setdefault(dd, 0)
        kb.setdefault(dd, 0)
        dat.setdefault(dd, 0)
    okt.setdefault("/", 0)
    kb.setdefault("/", 0)
    dat.setdefault("/", 0)

    with open(os.path.join(arbeit, "soll"), "w") as f:
        for d in sorted(okt):
            f.write("%s %d %d %d\n" % (d, okt[d], kb[d], dat[d]))

    mit = sum(1 for x in sz if x > 0)
    print("tree: %d files (%d with content), %d folders, %d octets, "
          "%d KiB-Bloecke"
          % (n, mit, len(seen), okt["/data"], kb["/data"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
