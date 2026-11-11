#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import subprocess
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import firnenv

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CC = firnenv.firnc_path(ROOT)


def einmal(file, profil_app=False):
    env = dict(os.environ)
    env["FIRNLIB"] = os.path.join(ROOT, "lib")
    args = [CC]
    if profil_app:
        args += ["-c", "--profile=app"]
    args += [file, "-o", "/tmp/masse.o"]
    r = subprocess.run(args, capture_output=True, text=True, env=env, cwd=ROOT)
    if r.returncode == 0:
        return 0
    lines = open(file).read().split("\n")
    n = 0
    for m in re.finditer(
            r"array literal has (\d+) elements, (\d+) are expected\n"
            r"\s*-->\s*([^\s:]+):(\d+):", r.stderr):
        ist, soll, wo, zl = int(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4))
        if os.path.abspath(os.path.join(ROOT, wo)) != os.path.abspath(file):
            continue
        z = lines[zl - 1]
        new = re.sub(r"\[u8;\s*%d\]" % soll, "[u8; %d]" % ist, z, count=1)
        if new != z:
            lines[zl - 1] = new
            n += 1
    if n:
        open(file, "w").write("\n".join(lines))
    return n


def main():
    app = "--app" in sys.argv
    for d in [a for a in sys.argv[1:] if a != "--app"]:
        for _ in range(40):
            if einmal(d, app) == 0:
                break
        print("masse: %s" % d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
