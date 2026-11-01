#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    bigfs.py <arbeitsverzeichnis> [<num der dateien>]
"""

import os
import sys

WOERTER = ["kupfer", "07", "datei", "quaste"]

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


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    arbeit = argv[1]
    n = int(argv[2]) if len(argv) > 2 else 4000
    os.makedirs(arbeit, exist_ok=True)
    list_2 = names(n)

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
    for path_2, name in list_2:
        rows.append("%s/%s=" % (path_2, name))
    with open(os.path.join(arbeit, "angaben"), "w") as f:
        f.write("\n".join(rows) + "\n")

    with open(os.path.join(arbeit, "namen"), "w") as f:
        for path_2, name in list_2:
            f.write("%s/%s\n" % (path_2, name))

    everything = [name for _, name in list_2]
    everything += [p.strip("/").split("/")[-1] for p in sorted(seen)]
    everything += ["data"]
    with open(os.path.join(arbeit, "erwartet"), "w") as f:
        for w in WOERTER:
            f.write("%s %d\n"
                    % (w, sum(1 for x in everything if w.lower() in x.lower())))
    print("big: %d files, %d folders, %d names"
          % (n, len(seen), len(everything)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
