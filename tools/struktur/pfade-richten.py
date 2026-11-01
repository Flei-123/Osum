#!/usr/bin/env python3

import os
import re
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MUSTER = re.compile(r"kernel/([a-z0-9_]+)\.fi")


def ort_von(name):
    for stamm, verz, names in os.walk(os.path.join(WURZEL, "kernel")):
        verz[:] = [d for d in verz if d not in ("user", "app")]
        if name + ".fi" in names:
            p = os.path.join(stamm, name + ".fi")
            return os.path.relpath(p, WURZEL)
    return None


def dateien():
    for stamm, verz, names in os.walk(WURZEL):
        verz[:] = [d for d in verz
                   if d not in (".git", "kernel", "vendor", "docs", "lib")]
        for n in names:
            if n.endswith((".sh", ".py")) or n == "test.sh":
                p = os.path.join(stamm, n)
                rel = os.path.relpath(p, WURZEL)
                if rel.startswith("tools/struktur/"):
                    continue
                yield p, rel


def main():
    trocken = "--trocken" in sys.argv
    cache = {}
    n_lines = 0
    n_dateien = 0
    for p, rel in dateien():
        try:
            with open(p, "rb") as f:
                roh = f.read().decode("utf-8", "replace")
        except OSError:
            continue
        if "kernel/" not in roh:
            continue
        zeilen = roh.split("\n")
        geaendert = False
        for i, z in enumerate(zeilen):
            nackt = z.lstrip()
            if nackt.startswith("#") or nackt.startswith("//"):
                continue
            if "kernel/" not in z:
                continue

            def ersetze(m):
                nonlocal geaendert
                name = m.group(1)
                alt = "kernel/%s.fi" % name
                if os.path.exists(os.path.join(WURZEL, alt)):
                    return m.group(0)
                if name not in cache:
                    cache[name] = ort_von(name)
                new = cache[name]
                if not new or new == alt:
                    return m.group(0)
                geaendert = True
                return new

            new_z = MUSTER.sub(ersetze, z)
            if new_z != z:
                if trocken:
                    print("  %s:%d" % (rel, i + 1))
                    print("    - %s" % z.strip()[:110])
                    print("    + %s" % new_z.strip()[:110])
                zeilen[i] = new_z
                n_lines += 1
        if geaendert:
            n_dateien += 1
            if not trocken:
                with open(p, "w", encoding="utf-8") as f:
                    f.write("\n".join(zeilen))
    word = "waeren zu richten" if trocken else "gerichtet"
    print("%d Zeilen in %d Dateien %s" % (n_lines, n_dateien, word))
    return 0


if __name__ == "__main__":
    sys.exit(main())
