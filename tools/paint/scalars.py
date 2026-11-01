#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HIER, "..", ".."))

CONST = re.compile(
    r"^const\s+(S_[A-Z0-9_]+)\s*:\s*u64\s*=\s*(0x[0-9A-Fa-f]+)\s*(//.*)?$")
NUM = re.compile(
    r"^const\s+([A-Z0-9_]+)\s*:\s*u64\s*=\s*(0x[0-9A-Fa-f]+|\d+)", re.M)
WOERTER = re.compile(r"(\d+)\s+W[oe]+rter")
OKTETTE = re.compile(r"(\d+)\s+Oktette")

LEN_AUS = {
    ("wm.fi", "S_DECO"): "DECO_SLOTS",
}


def laengen(path_2):
    with open(path_2, "rb") as fh:
        text = fh.read().decode("utf-8", "replace")
    konst = {}
    for m in NUM.finditer(text):
        konst[m.group(1)] = int(m.group(2), 0)
    aus = []
    file_2 = os.path.basename(path_2)
    for nr, line in enumerate(text.splitlines(), 1):
        m = CONST.match(line.strip())
        if not m:
            continue
        name = m.group(1)
        value = int(m.group(2), 0)
        if value % 8 != 0:
            continue
        kommentar = m.group(3) or ""
        n = 8
        w = WOERTER.search(kommentar)
        o = OKTETTE.search(kommentar)
        if w:
            n = int(w.group(1)) * 8
        elif o:
            n = int(o.group(1))
        key = (file_2, name)
        if key in LEN_AUS:
            k = LEN_AUS[key]
            if k in konst:
                n = konst[k] * 8
        aus.append((name, value, n, nr))
    return aus


def check(path_2):
    eintraege = laengen(path_2)
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
        kdir = os.path.join(ROOT, "kernel")
        dateien = sorted(os.path.join(kdir, f)
                         for f in os.listdir(kdir) if f.endswith(".fi"))
    gesamt = 0
    bad_2 = 0
    for p in dateien:
        eintraege, treffer = check(p)
        gesamt += len(eintraege)
        rel = os.path.relpath(p, ROOT)
        for (an, aw, al, az, bn, bw, bl, bz) in treffer:
            bad_2 += 1
            print("  FAIL  %s: %s (0x%X, %d octets, line %d) and "
                  "%s (0x%X, %d Oktette, Zeile %d) ueberschneiden sich"
                  % (rel, an, aw, al, az, bn, bw, bl, bz))
    print("PAINT-SKALARE: %d Skalare in %d Dateien, %d Ueberschneidungen"
          % (gesamt, len(dateien), bad_2))
    if bad_2 == 0:
        print("  OK    no two scalars of a file lie on top of each other")
    return 1 if bad_2 else 0


if __name__ == "__main__":
    sys.exit(main())
