#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/erhebung.py -- die Ist-Aufnahme des Kernbaums.
#
# Dieses Werkzeug AENDERT NICHTS. Es liest jede `.fi`-Datei unter
# `kernel/`, sammelt ihre `import`-Zeilen und beantwortet damit vier
# Fragen, die man einem flachen Verzeichnis mit 137 Dateien sonst nicht
# ansieht:
#
#   1. WER RUFT WEN? Die Kanten des Abhaengigkeitsgraphen.
#   2. WO SIND ZYKLEN? Starke Zusammenhangskomponenten (Tarjan). Ein
#      Zyklus ist kein Fehler in Firn -- der Uebersetzer liest den ganzen
#      Baum auf einmal --, aber er sagt, welche Dateien man NICHT
#      einzeln herausloesen kann.
#   3. WIE SCHWER WIEGT EINE DATEI? Zeilen, eingehende und ausgehende
#      Kanten.
#   4. HAELT DIE SCHICHTREGEL? Dazu liest es `tools/struktur/schichten.txt`
#      (Zuordnung Datei -> Schicht) und zaehlt, wie viele Kanten die
#      Regel einhalten und wie viele sie brechen.
#
# WICHTIG ZUR MODULAUFLOESUNG (gemessen in /root/firn/compiler/src/modules.rs):
# `import a.b.c` laedt `a/b/c.fi` und spricht das Modul unter dem LETZTEN
# Namensteil an (`c`). Ein Verschieben von `x.fi` nach `unter/x.fi`
# aendert also NUR die import-Zeilen der Aufrufer -- KEINE Aufrufstelle
# im Rumpf. Genau das macht diese Runde ueberhaupt moeglich.
#
# Aufruf:
#   python3 tools/struktur/erhebung.py            # Textbericht
#   python3 tools/struktur/erhebung.py --json     # Maschinenlesbar
#   python3 tools/struktur/erhebung.py --pruefen  # nur Regelbrueche, Code 1

import json
import os
import re
import sys

WURZEL = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KERN = os.path.join(WURZEL, "kernel")
SCHICHTDATEI = os.path.join(WURZEL, "tools", "struktur", "schichten.txt")

# `import foo`, `import arch.x86_64.apic` -- am Zeilenanfang, keine
# Fortsetzung. Kommentare (`//`) zaehlen nicht.
IMPORT_RE = re.compile(r"^[ \t]*import[ \t]+([A-Za-z_][A-Za-z0-9_.]*)[ \t]*(?://.*)?$")


def lies(pfad):
    """Liest eine Datei als Text. `kmain.fi` enthaelt eingebettete
    Oktette, die kein UTF-8 sind (ein eingebautes Abbild) -- deshalb
    'replace' statt eines Abbruchs."""
    with open(pfad, "rb") as f:
        return f.read().decode("utf-8", "replace")


def sammle():
    """Alle .fi-Dateien unter kernel/, als Modulname -> Angaben.

    Der Modulname ist der Dateiname ohne Endung, denn genau so spricht
    Firn ein Modul an (letzter Pfadteil). Zwei Dateien gleichen Namens
    in verschiedenen Ordnern waeren eine Namenskollision; das meldet
    diese Funktion, statt sie stillschweigend zu ueberschreiben."""
    module = {}
    kollisionen = []
    for stamm, _, namen in os.walk(KERN):
        for n in sorted(namen):
            if not n.endswith(".fi"):
                continue
            pfad = os.path.join(stamm, n)
            rel = os.path.relpath(pfad, WURZEL)
            name = n[:-3]
            src = lies(pfad)
            zeilen = src.count("\n") + (0 if src.endswith("\n") or not src else 1)
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
                "zeilen": zeilen,
                "importe": sorted(set(ziele)),
            }
    return module, kollisionen


def tarjan(knoten, kanten):
    """Starke Zusammenhangskomponenten, iterativ (der Graph ist zu tief
    fuer Rekursion in Python). Liefert nur Komponenten mit mehr als
    einem Knoten -- das sind die echten Zyklen."""
    index = {}
    tief = {}
    aufstapel = set()
    stapel = []
    ergebnis = []
    zaehler = [0]
    for start in knoten:
        if start in index:
            continue
        # (Knoten, Iterator ueber seine Nachbarn)
        arbeit = [(start, iter(kanten.get(start, ())))]
        index[start] = tief[start] = zaehler[0]
        zaehler[0] += 1
        stapel.append(start)
        aufstapel.add(start)
        while arbeit:
            k, it = arbeit[-1]
            fortschritt = False
            for n in it:
                if n not in knoten:
                    continue
                if n not in index:
                    index[n] = tief[n] = zaehler[0]
                    zaehler[0] += 1
                    stapel.append(n)
                    aufstapel.add(n)
                    arbeit.append((n, iter(kanten.get(n, ()))))
                    fortschritt = True
                    break
                if n in aufstapel:
                    tief[k] = min(tief[k], index[n])
            if fortschritt:
                continue
            arbeit.pop()
            if arbeit:
                el = arbeit[-1][0]
                tief[el] = min(tief[el], tief[k])
            if tief[k] == index[k]:
                komp = []
                while True:
                    w = stapel.pop()
                    aufstapel.discard(w)
                    komp.append(w)
                    if w == k:
                        break
                if len(komp) > 1:
                    ergebnis.append(sorted(komp))
    return sorted(ergebnis, key=lambda c: (-len(c), c[0]))


def lies_schichten():
    """`schichten.txt`: je Zeile `schicht modul`, plus `#rang schicht n`
    fuer die Ordnung. Fehlt die Datei, gibt es keine Regelpruefung."""
    if not os.path.exists(SCHICHTDATEI):
        return {}, {}
    zuord = {}
    rang = {}
    for z in lies(SCHICHTDATEI).splitlines():
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


def pruefe_regel(module, zuord, rang):
    """DIE REGEL: eine Schicht darf nur auf Schichten mit KLEINEREM oder
    GLEICHEM Rang zugreifen. Gleicher Rang ist erlaubt (innerhalb einer
    Schicht darf man sich kennen), hoeher ist ein Bruch -- der Treiber
    darf die Oberflaeche nicht rufen.

    Liefert (halten, brueche_liste)."""
    halten = 0
    brueche = []
    for name, ang in sorted(module.items()):
        vs = zuord.get(name)
        if vs is None:
            continue
        for ziel in ang["importe"]:
            zs = zuord.get(ziel)
            if zs is None:
                continue
            rv = rang.get(vs)
            rz = rang.get(zs)
            if rv is None or rz is None:
                continue
            if rz <= rv:
                halten += 1
            else:
                brueche.append((name, vs, ziel, zs))
    return halten, brueche


def main():
    modus = sys.argv[1] if len(sys.argv) > 1 else ""
    module, kollisionen = sammle()
    kanten = {k: v["importe"] for k, v in module.items()}
    # Eingangsgrad: wie viele andere Dateien brauchen diese hier.
    ein = {k: 0 for k in module}
    for k, zs in kanten.items():
        for z in zs:
            if z in ein:
                ein[z] += 1
    zyklen = tarjan(set(module), kanten)
    zuord, rang = lies_schichten()
    halten, brueche = pruefe_regel(module, zuord, rang)

    if modus == "--json":
        print(json.dumps({
            "module": module, "zyklen": zyklen, "halten": halten,
            "brueche": brueche, "kollisionen": kollisionen,
            "eingang": ein,
        }, indent=1, sort_keys=True))
        return 0

    if modus == "--pruefen":
        # Gegenprobe-tauglich: NUR das Urteil, Code 1 bei Bruch.
        if not zuord:
            print("KEINE Schichtzuordnung (tools/struktur/schichten.txt) -- nichts geprueft")
            return 1
        print("Schichtregel: %d Kanten halten, %d brechen" % (halten, len(brueche)))
        for v, vs, z, zs in brueche:
            print("  BRUCH %s (%s) -> %s (%s)" % (v, vs, z, zs))
        return 1 if brueche else 0

    gesamt = sum(m["zeilen"] for m in module.values())
    print("== ERHEBUNG kernel/ ==")
    print("Dateien: %d, Zeilen: %d, Kanten: %d"
          % (len(module), gesamt, sum(len(v) for v in kanten.values())))
    if kollisionen:
        print("NAMENSKOLLISIONEN: %s" % kollisionen)
    print()
    print("-- die 15 groessten Dateien --")
    for n, m in sorted(module.items(), key=lambda kv: -kv[1]["zeilen"])[:15]:
        print("  %-14s %6d Zeilen  ein:%3d aus:%3d  %s"
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
        print("  halten: %d, brechen: %d" % (halten, len(brueche)))
        for v, vs, z, zs in brueche[:40]:
            print("    BRUCH %s (%s) -> %s (%s)" % (v, vs, z, zs))
    else:
        print("-- Schichtregel: noch keine Zuordnung --")
    return 0


if __name__ == "__main__":
    sys.exit(main())
