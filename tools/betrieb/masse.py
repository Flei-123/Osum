#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/betrieb/masse.py -- die Laengen der Textliterale nachziehen.

    masse.py <datei.fi> [<datei.fi> ...]

In Firn traegt ein Textliteral seine Laenge im Typ (`[u8; 27]`), und der
Uebersetzer zaehlt `\\0`, `\\t` und `\\n` als je EIN Oktett. Wer eine
Meldung umformuliert, muss die Zahl mitziehen; wer es vergisst, bekommt
`array literal has 47 elements, 44 are expected`.

Dieses Skript ruft den Uebersetzer, liest genau diese Meldung und
schreibt die Zahl in der genannten Zeile richtig. Es ist ein
Schreibhelfer und kein Teil des Systems.
"""
import re
import subprocess
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CC = os.path.join(ROOT, "vendor/firn/bin/firnc")


def einmal(datei, profil_app=False):
    env = dict(os.environ)
    env["FIRNLIB"] = os.path.join(ROOT, "lib")
    args = [CC]
    if profil_app:
        args += ["-c", "--profile=app"]
    args += [datei, "-o", "/tmp/masse.o"]
    r = subprocess.run(args, capture_output=True, text=True, env=env, cwd=ROOT)
    if r.returncode == 0:
        return 0
    zeilen = open(datei).read().split("\n")
    n = 0
    for m in re.finditer(
            r"array literal has (\d+) elements, (\d+) are expected\n"
            r"\s*-->\s*([^\s:]+):(\d+):", r.stderr):
        ist, soll, wo, zl = int(m.group(1)), int(m.group(2)), m.group(3), int(m.group(4))
        if os.path.abspath(os.path.join(ROOT, wo)) != os.path.abspath(datei):
            continue
        z = zeilen[zl - 1]
        neu = re.sub(r"\[u8;\s*%d\]" % soll, "[u8; %d]" % ist, z, count=1)
        if neu != z:
            zeilen[zl - 1] = neu
            n += 1
    if n:
        open(datei, "w").write("\n".join(zeilen))
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
