#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    icons.py build  <ausgabeverzeichnis>
    icons.py kern   <kernel/net/netmark.fi>
    icons.py check [--kern kernel/net/netmark.fi]
"""

import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HIER)
sys.path.insert(0, os.path.join(ROOT, "k15"))
import icon as symmod  # noqa: E402

SOURCE = os.path.join(ROOT, "..", "assets", "netview")

ZUSTAENDE = ["state-nocarrier", "state-noip", "state-noroute", "state-online"]
MERKMALE = ["mark-filtered", "mark-faked", "mark-none"]
SYSTEM = ["sys-faking"]
KACHELN = ["tile-fake", "tile-net", "tile-hide",
           "tile-dark", "tile-power", "tile-tile"]

CROSS = [("sys-faking", "mark-faked")]

CROSS_TILE = [("tile-fake", "state-online"),
                ("tile-fake", "state-nocarrier"),
                ("tile-hide", "state-online"),
                ("tile-net", "state-online")]

FILE_NAME = {"ink": "fg", "dim": "dim", "accent": "accent",
              "warn": "focus", "panel": "panel"}


def schema_read(path_2):
    values = {}
    for roh in open(path_2, encoding="ascii"):
        roh = roh.strip()
        if not roh or roh.startswith("#") or "=" not in roh:
            continue
        k, _, v = roh.partition("=")
        values[k.strip()] = int(v.strip(), 16)
    aus = {}
    for rolle, key in FILE_NAME.items():
        if key not in values:
            raise SystemExit("icons: %s hat kein %s=" % (path_2, key))
        aus[rolle] = values[key]
    return aus


SCHEMEN = {
    "dark": schema_read(os.path.join(SOURCE, "theme-dark")),
    "light": schema_read(os.path.join(SOURCE, "theme-light")),
}

MIN_CONTRAST = 4.5
MIN_UNTERSCHIED = 33



def linear(k):
    k = k / 255.0
    if k <= 0.03928:
        return k / 12.92
    return ((k + 0.055) / 1.055) ** 2.4


def brightness(rgb):
    r, g, b = (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)


def contrast(a, b):
    la, lb = brightness(a), brightness(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)



def zeichnung(name):
    return os.path.join(SOURCE, name + ".txt")


def read_2(name):
    return symmod.read_2(zeichnung(name))


def schattenriss(name):
    palette, rows = read_2(name)
    aus = set()
    for y, z in enumerate(rows):
        for x, c in enumerate(z):
            if palette[c] is not None:
                aus.add((x, y))
    return aus, len(rows[0]), len(rows)


def bitreihen(name):
    palette, rows = read_2(name)
    w = len(rows[0])
    reihen = []
    for z in rows:
        maske = 0
        rollen = 0
        for x, c in enumerate(z):
            v = palette[c]
            if v is None:
                continue
            maske |= 1 << (w - 1 - x)
            nr = v[1] if isinstance(v, tuple) else 15
            rollen |= nr << (x * 4)
        reihen.append((maske, rollen))
    return reihen, w, len(rows)



def check_gestaltung(say_2=True):
    error = 0

    def say(t):
        if say_2:
            print(t)

    say("== Contrast of each role against the area, light and dark ==")
    for sn, s in sorted(SCHEMEN.items()):
        for rolle in ("ink", "dim", "accent", "warn"):
            k = contrast(s[rolle], s["panel"])
            gut = k >= MIN_CONTRAST
            error += 0 if gut else 1
            say("  %-5s %-7s %5.2f:1  %s"
                % (sn, rolle, k, "ok" if gut else "ZU WENIG"))

    for title, gruppe in (("Systemzustand", ZUSTAENDE), ("Merkmal", MERKMALE),
                          ("Kachel", KACHELN)):
        say("== %s: SHAPE BEFORE COLOR -- silhouettes against each other ==" % title)
        risse = {n: schattenriss(n) for n in gruppe}
        for i in range(len(gruppe)):
            for j in range(i + 1, len(gruppe)):
                a, wa, ha = risse[gruppe[i]]
                b, wb, hb = risse[gruppe[j]]
                if (wa, ha) != (wb, hb):
                    say("  %s and %s are not the same size" % (gruppe[i], gruppe[j]))
                    error += 1
                    continue
                u = len(a | b)
                d = len(a ^ b)
                pz = 100 * d // u if u else 0
                gut = pz >= MIN_UNTERSCHIED
                error += 0 if gut else 1
                say("  %-15s vs %-15s %3d von %3d = %2d%%  %s"
                    % (gruppe[i].split("-", 1)[1], gruppe[j].split("-", 1)[1], d, u, pz,
                       "ok" if gut else "ZU AEHNLICH"))

    say("== ACROSS the groups: glyphs that stand side by side ==")
    for a_n, b_n in CROSS + CROSS_TILE:
        a, wa, ha = schattenriss(a_n)
        b, wb, hb = schattenriss(b_n)
        if (wa, ha) != (wb, hb):
            say("  %s and %s are not the same size" % (a_n, b_n))
            error += 1
            continue
        u = len(a | b)
        d = len(a ^ b)
        pz = 100 * d // u if u else 0
        gut = pz >= MIN_UNTERSCHIED
        error += 0 if gut else 1
        say("  %-15s vs %-15s %3d von %3d = %2d%%  %s"
            % (a_n, b_n, d, u, pz, "ok" if gut else "ZU AEHNLICH"))
    return error


def dims():
    aus = []
    for n in ZUSTAENDE + MERKMALE + SYSTEM + KACHELN:
        tear, w, h = schattenriss(n)
        aus.append((n, w, h, len(tear), w * h))
    return aus



HEADER = """profile kernel

export { W, H, COUNT, M_FILTERED, M_FAKED, M_NONE, mask_at, role_at }

const W: u64 = %(w)d
const H: u64 = %(h)d
const COUNT: u64 = %(count)d

const M_FILTERED: u64 = 0
const M_FAKED: u64 = 1
const M_NONE: u64 = 2

fn mask_at(m: u64, y: u64) -> u64 {
    if m >= COUNT || y >= H {
        return 0
    }
%(masken)s    return 0
}

fn role_at(m: u64, y: u64) -> u64 {
    if m >= COUNT || y >= H {
        return 0
    }
%(rollen)s    return 0
}
"""


def kernquelle():
    reihen = []
    w = h = None
    for n in MERKMALE:
        r, rw, rh = bitreihen(n)
        if w is None:
            w, h = rw, rh
        elif (rw, rh) != (w, h):
            raise SystemExit("icons: %s ist %dx%d, erwartet %dx%d"
                             % (n, rw, rh, w, h))
        reihen.append(r)

    def board(index):
        t = []
        for m, r in enumerate(reihen):
            for y, paar in enumerate(r):
                if paar[index] == 0:
                    continue
                t.append("    if m == %d && y == %d {\n        return 0x%X\n    }\n"
                         % (m, y, paar[index]))
        return "".join(t)

    return HEADER % {
        "w": w, "h": h, "count": len(MERKMALE),
        "masken": board(0), "rollen": board(1),
    }


def assemble(target):
    os.makedirs(target, exist_ok=True)
    n = 0
    for name in ZUSTAENDE + MERKMALE + SYSTEM + KACHELN:
        d = symmod.build(zeichnung(name))
        with open(os.path.join(target, name), "wb") as f:
            f.write(d)
        n += 1
    return n


def main(argv):
    if len(argv) >= 3 and argv[1] == "bauen":
        n = assemble(argv[2])
        print("icons: %d Symbole nach %s" % (n, argv[2]))
        return 0
    if len(argv) >= 3 and argv[1] == "kern":
        with open(argv[2], "w", encoding="ascii") as f:
            f.write(kernquelle())
        print("icons: %s geschrieben" % argv[2])
        return 0
    if len(argv) >= 2 and argv[1] == "masse":
        for n, w, h, deck, ganz in dims():
            print("%-18s %2dx%-2d  %3d von %3d eingefaerbt = %d%%"
                  % (n, w, h, deck, ganz, 100 * deck // ganz))
        return 0
    if len(argv) >= 2 and argv[1] == "pruefe":
        error = check_gestaltung()
        kdatei = os.path.join(ROOT, "..", "kernel", "net", "netmark.fi")
        if "--kern" in argv:
            kdatei = argv[argv.index("--kern") + 1]
        soll = kernquelle()
        try:
            ist = open(kdatei, encoding="ascii").read()
        except OSError:
            ist = None
        if ist is None:
            print("== %s fehlt ==" % kdatei)
            error += 1
        elif ist != soll:
            print("== %s deviates from the drawing ==" % kdatei)
            error += 1
        else:
            print("== %s matches the drawing octet for octet ==" % kdatei)
        print("icons: %d Beanstandungen" % error)
        return 1 if error else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
