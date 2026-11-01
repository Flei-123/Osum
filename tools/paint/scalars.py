#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
#
#     const S_TILE: u64 = 0x180      // Runde TILING
#     const S_DECO: u64 = 0x180      // Runde THEME, elf Woerter
#
#
#
#   ./tools/paint/scalars.py [dateien...]
#
#
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.normpath(os.path.join(HIER, "..", ".."))

CONST = re.compile(
    r"^const\s+(S_[A-Z0-9_]+)\s*:\s*u64\s*=\s*(0x[0-9A-Fa-f]+)\s*(//.*)?$")
ZAHL = re.compile(
    r"^const\s+([A-Z0-9_]+)\s*:\s*u64\s*=\s*(0x[0-9A-Fa-f]+|\d+)", re.M)
WOERTER = re.compile(r"(\d+)\s+W[oe]+rter")
OKTETTE = re.compile(r"(\d+)\s+Oktette")

LAENGE_AUS = {
    ("wm.fi", "S_DECO"): "DECO_SLOTS",
}


def laengen(pfad):
    """[(name, anfang, oktette, zeile)] fuer eine Datei."""
    with open(pfad, "rb") as fh:
        text = fh.read().decode("utf-8", "replace")
    konst = {}
    for m in ZAHL.finditer(text):
        konst[m.group(1)] = int(m.group(2), 0)
    aus = []
    datei = os.path.basename(pfad)
    for nr, zeile in enumerate(text.splitlines(), 1):
        m = CONST.match(zeile.strip())
        if not m:
            continue
        name = m.group(1)
        wert = int(m.group(2), 0)
        if wert % 8 != 0:
            continue
        kommentar = m.group(3) or ""
        n = 8
        w = WOERTER.search(kommentar)
        o = OKTETTE.search(kommentar)
        if w:
            n = int(w.group(1)) * 8
        elif o:
            n = int(o.group(1))
        schluessel = (datei, name)
        if schluessel in LAENGE_AUS:
            k = LAENGE_AUS[schluessel]
            if k in konst:
                n = konst[k] * 8
        aus.append((name, wert, n, nr))
    return aus


def pruefen(pfad):
    eintraege = laengen(pfad)
    treffer = []
    for i in range(len(eintraege)):
        an, aw, al, az = eintraege[i]
        for j in range(i + 1, len(eintraege)):
            bn, bw, bl, bz = eintraege[j]
            if aw < bw + bl and bw < aw + al:
                treffer.append((an, aw, al, az, bn, bw, bl, bz))
    return eintraege, treffer


def main():
    dateien = sys.argv[1:]
    if not dateien:
        kdir = os.path.join(WURZEL, "kernel")
        dateien = sorted(os.path.join(kdir, f)
                         for f in os.listdir(kdir) if f.endswith(".fi"))
    gesamt = 0
    schlecht = 0
    for p in dateien:
        eintraege, treffer = pruefen(p)
        gesamt += len(eintraege)
        rel = os.path.relpath(p, WURZEL)
        for (an, aw, al, az, bn, bw, bl, bz) in treffer:
            schlecht += 1
            print("  FAIL  %s: %s (0x%X, %d octets, line %d) and "
                  "%s (0x%X, %d Oktette, Zeile %d) ueberschneiden sich"
                  % (rel, an, aw, al, az, bn, bw, bl, bz))
    print("PAINT-SKALARE: %d Skalare in %d Dateien, %d Ueberschneidungen"
          % (gesamt, len(dateien), schlecht))
    if schlecht == 0:
        print("  OK    no two scalars of a file lie on top of each other")
    return 1 if schlecht else 0


if __name__ == "__main__":
    sys.exit(main())
