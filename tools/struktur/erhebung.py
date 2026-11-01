#!/usr/bin/env python3

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(ROOT, "kernel")
SCHICHTDATEI = os.path.join(ROOT, "tools", "struktur", "schichten.txt")

IMPORT_RE = re.compile(r"^[ \t]*import[ \t]+([A-Za-z_][A-Za-z0-9_.]*)[ \t]*(?://.*)?$")


def read_2(path_2):
    with open(path_2, "rb") as f:
        return f.read().decode("utf-8", "replace")


def sammle():
    module = {}
    kollisionen = []
    for stamm, _, names in os.walk(KERN):
        for n in sorted(names):
            if not n.endswith(".fi"):
                continue
            path_2 = os.path.join(stamm, n)
            rel = os.path.relpath(path_2, ROOT)
            name = n[:-3]
            src = read_2(path_2)
            lines = src.count("\n") + (0 if src.endswith("\n") or not src else 1)
            ziele = []
            for z in src.splitlines():
                m = IMPORT_RE.match(z)
                if m:
                    ziele.append(m.group(1).split(".")[-1])
            if name in module:
                kollisionen.append((name, module[name]["pfad"], rel))
                continue
            module[name] = {
                "pfad": rel,
                "ordner": os.path.relpath(stamm, KERN).replace(os.sep, "/"),
                "zeilen": lines,
                "importe": sorted(set(ziele)),
            }
    return module, kollisionen


def tarjan(node, edges):
    index = {}
    tief = {}
    aufstapel = set()
    stack = []
    ergebnis = []
    counter = [0]
    for start in node:
        if start in index:
            continue
        arbeit = [(start, iter(edges.get(start, ())))]
        index[start] = tief[start] = counter[0]
        counter[0] += 1
        stack.append(start)
        aufstapel.add(start)
        while arbeit:
            k, it = arbeit[-1]
            progress = False
            for n in it:
                if n not in node:
                    continue
                if n not in index:
                    index[n] = tief[n] = counter[0]
                    counter[0] += 1
                    stack.append(n)
                    aufstapel.add(n)
                    arbeit.append((n, iter(edges.get(n, ()))))
                    progress = True
                    break
                if n in aufstapel:
                    tief[k] = min(tief[k], index[n])
            if progress:
                continue
            arbeit.pop()
            if arbeit:
                el = arbeit[-1][0]
                tief[el] = min(tief[el], tief[k])
            if tief[k] == index[k]:
                komp = []
                while True:
                    w = stack.pop()
                    aufstapel.discard(w)
                    komp.append(w)
                    if w == k:
                        break
                if len(komp) > 1:
                    ergebnis.append(sorted(komp))
    return sorted(ergebnis, key=lambda c: (-len(c), c[0]))


def read_schichten():
    if not os.path.exists(SCHICHTDATEI):
        return {}, {}
    zuord = {}
    rang = {}
    for z in read_2(SCHICHTDATEI).splitlines():
        z = z.strip()
        if not z:
            continue
        if z.startswith("#rang"):
            t = z.split()
            if len(t) == 3:
                rang[t[1]] = int(t[2])
            continue
        if z.startswith("#"):
            continue
        t = z.split()
        if len(t) == 2:
            zuord[t[1]] = t[0]
    return zuord, rang


def check_rule(module, zuord, rang):
    hold = 0
    brueche = []
    for name, ang in sorted(module.items()):
        vs = zuord.get(name)
        if vs is None:
            continue
        for target in ang["importe"]:
            zs = zuord.get(target)
            if zs is None:
                continue
            rv = rang.get(vs)
            rz = rang.get(zs)
            if rv is None or rz is None:
                continue
            if rz <= rv:
                hold += 1
            else:
                brueche.append((name, vs, target, zs))
    return hold, brueche


def main():
    modus = sys.argv[1] if len(sys.argv) > 1 else ""
    module, kollisionen = sammle()
    edges = {k: v["importe"] for k, v in module.items()}
    ein = {k: 0 for k in module}
    for k, zs in edges.items():
        for z in zs:
            if z in ein:
                ein[z] += 1
    zyklen = tarjan(set(module), edges)
    zuord, rang = read_schichten()
    hold, brueche = check_rule(module, zuord, rang)

    if modus == "--json":
        print(json.dumps({
            "module": module, "zyklen": zyklen, "halten": hold,
            "brueche": brueche, "kollisionen": kollisionen,
            "eingang": ein,
        }, indent=1, sort_keys=True))
        return 0

    if modus == "--pruefen":
        if not zuord:
            print("KEINE Schichtzuordnung (tools/struktur/schichten.txt) -- nichts geprueft")
            return 1
        print("Schichtregel: %d Kanten halten, %d brechen" % (hold, len(brueche)))
        for v, vs, z, zs in brueche:
            print("  BRUCH %s (%s) -> %s (%s)" % (v, vs, z, zs))
        return 1 if brueche else 0

    gesamt = sum(m["zeilen"] for m in module.values())
    print("== ERHEBUNG kernel/ ==")
    print("Dateien: %d, Zeilen: %d, Kanten: %d"
          % (len(module), gesamt, sum(len(v) for v in edges.values())))
    if kollisionen:
        print("NAMENSKOLLISIONEN: %s" % kollisionen)
    print()
    print("-- die 15 groessten Dateien --")
    for n, m in sorted(module.items(), key=lambda kv: -kv[1]["zeilen"])[:15]:
        print("  %-14s %6d lines  in:%3d out:%3d  %s"
              % (n, m["zeilen"], ein[n], len(m["importe"]), m["pfad"]))
    print()
    print("-- die 15 meistgerufenen Module --")
    for n, c in sorted(ein.items(), key=lambda kv: -kv[1])[:15]:
        print("  %-14s von %3d Dateien gerufen" % (n, c))
    print()
    print("-- Zyklen (starke Zusammenhangskomponenten > 1) --")
    if not zyklen:
        print("  keine")
    for z in zyklen:
        print("  [%d] %s" % (len(z), " ".join(z)))
    print()
    if zuord:
        print("-- Schichtregel --")
        print("  halten: %d, brechen: %d" % (hold, len(brueche)))
        for v, vs, z, zs in brueche[:40]:
            print("    BRUCH %s (%s) -> %s (%s)" % (v, vs, z, zs))
    else:
        print("-- layer rule: no assignment yet --")
    return 0


if __name__ == "__main__":
    sys.exit(main())
