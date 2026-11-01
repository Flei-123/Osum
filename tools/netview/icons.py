#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/netview/icons.py -- die Symbole der Runde NETVIEW, aus EINER Quelle.

Der Nachtrag der Runde verlangt zwei Anzeigen, und sie werden an ZWEI
Stellen gemalt, die nichts miteinander zu tun haben:

  * die Taskleiste (`kernel/user/taskbar.fi`) -- Ring 3, malt eine
    OSYM-Datei von der Platte,
  * die Titelleiste (`kernel/ui/wm.fi`) -- der KERN, der keine Datei von der
    Platte liest, waehrend er ein Fenster zeichnet.

Zwei Stellen, ein Zeichen. Der bequeme Weg waere, die zwoelf mal zwoelf
Bildpunkte zweimal hinzuschreiben; das ist genau die Sorte Verdopplung,
die einen Monat spaeter zwei verschiedene Zeichen fuer dieselbe Sache
ergibt. Also: die ZEICHNUNG unter `assets/netview/*.txt` ist die Quelle,
und dieses Werkzeug macht daraus

  1. die OSYM-Dateien fuer die Platte (ueber `tools/k15/icon.py`,
     dasselbe Format wie jedes Buendelsymbol -- kein zweites),
  2. `kernel/net/netmark.fi`, den Kern-Teil: dieselben Zeichen als
     Bitreihen, damit `wm.fi` sie ohne Dateisystem malen kann.

UND ES PRUEFT SICH SELBST. `icons.py --pruefe` baut alles noch einmal und
vergleicht es mit dem, was im Baum liegt. Weicht `kernel/net/netmark.fi` von
der Zeichnung ab, faellt der Abnahmelauf durch -- eine erzeugte Datei
ohne diese Pruefung ist eine Verdopplung mit Zusatzschritt.

DIE GESTALTUNGSREGELN, gegen die hier GEMESSEN wird (nicht behauptet):

  * FORM VOR FARBE. Wer Rot und Gruen nicht unterscheiden kann, muss die
    Zeichen trotzdem auseinanderhalten. Also wird jedes Zeichen auf
    seinen SCHATTENRISS reduziert -- jede Farbe zu einer -- und je zwei
    Schattenrisse muessen sich um mindestens ein Drittel der Bildpunkte
    unterscheiden, die ueberhaupt einer von beiden faerbt.
  * KONTRAST. Jede Rolle gegen die Flaeche, auf der sie liegt,
    mindestens 4.5:1 nach WCAG -- in HELL UND IN DUNKEL.
  * ZIELGROSSE. Gezeichnet wird in der Groesse, in der es haengt: 16x16
    fuer den Systemzustand, 12x12 fuer das Merkmal am Programm. Ein
    Symbol, das bei 24 entworfen und auf 16 gequetscht wird, verliert
    genau den Bildpunkt, an dem man es erkannt hat.

Verwendung:
    icons.py bauen  <ausgabeverzeichnis>
    icons.py kern   <kernel/net/netmark.fi>
    icons.py pruefe [--kern kernel/net/netmark.fi]
"""

import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
sys.path.insert(0, os.path.join(WURZEL, "k15"))
import icon as symmod  # noqa: E402

SOURCE = os.path.join(WURZEL, "..", "assets", "netview")

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


def schema_read(pfad):
    values = {}
    for roh in open(pfad, encoding="ascii"):
        roh = roh.strip()
        if not roh or roh.startswith("#") or "=" not in roh:
            continue
        k, _, v = roh.partition("=")
        values[k.strip()] = int(v.strip(), 16)
    aus = {}
    for rolle, key_2 in FILE_NAME.items():
        if key_2 not in values:
            raise SystemExit("icons: %s hat kein %s=" % (pfad, key_2))
        aus[rolle] = values[key_2]
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


def lies(name):
    return symmod.lies(zeichnung(name))


def schattenriss(name):
    """Jede Farbe zu einer: WAS wird eingefaerbt, egal womit."""
    palette, zeilen = lies(name)
    aus = set()
    for y, z in enumerate(zeilen):
        for x, c in enumerate(z):
            if palette[c] is not None:
                aus.add((x, y))
    return aus, len(zeilen[0]), len(zeilen)


def bitreihen(name):
    """Das Zeichen als Reihen von Bits, hoechstwertiges Bit links, plus je
    Bildpunkt die Rollennummer. Fuer den Kern, der keine Datei liest."""
    palette, zeilen = lies(name)
    w = len(zeilen[0])
    reihen = []
    for z in zeilen:
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
    return reihen, w, len(zeilen)



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
    """Groesse und Deckung je Zeichen -- die Zahlen fuer die Doku."""
    aus = []
    for n in ZUSTAENDE + MERKMALE + SYSTEM + KACHELN:
        tear, w, h = schattenriss(n)
        aus.append((n, w, h, len(tear), w * h))
    return aus



HEADER = """// SPDX-License-Identifier: GPL-2.0-only
// kernel/net/netmark.fi -- ERZEUGT AUS assets/netview/mark-*.txt.
//
// NICHT VON HAND AENDERN. `tools/netview/icons.py kern` schreibt diese
// Datei, und `tools/netview/run.sh` baut sie im Abnahmelauf noch einmal
// und vergleicht sie Oktett fuer Oktett mit der, die im Baum liegt.
// Weicht sie ab, faellt der Lauf durch.
//
// WARUM ES SIE UEBERHAUPT GIBT. Dasselbe Zeichen steht an zwei Stellen
// auf dem Schirm: am Fensterknopf in der Taskleiste (Ring 3, liest die
// OSYM-Datei von der Platte) und in der TITELLEISTE (der Fensterserver,
// mitten im Zeichnen eines Fensters, ohne Dateisystem). Zwei Stellen
// duerfen nicht zwei Zeichnungen bedeuten -- also ist die Zeichnung die
// Quelle und diese Datei ihr Abdruck.
//
// EINE REIHE JE BILDZEILE: `maske` traegt je Bildpunkt ein Bit,
// hoechstwertiges Bit links; `rollen` traegt je Bildpunkt vier Bit mit
// der Farbrolle (1 ink, 2 dim, 3 accent, 4 warn, 5 panel), niedrigstes
// Nibble ganz links.

profile kernel

export { W, H, COUNT, M_FILTERED, M_FAKED, M_NONE, mask_at, role_at }

const W: u64 = %(w)d
const H: u64 = %(h)d
const COUNT: u64 = %(count)d

// Die Reihenfolge ist die der Sichten in `kernel/netview.fi`, ohne
// `real` -- der Normalfall bekommt kein Zeichen.
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


def bauen(target):
    os.makedirs(target, exist_ok=True)
    n = 0
    for name in ZUSTAENDE + MERKMALE + SYSTEM + KACHELN:
        d = symmod.baue(zeichnung(name))
        with open(os.path.join(target, name), "wb") as f:
            f.write(d)
        n += 1
    return n


def main(argv):
    if len(argv) >= 3 and argv[1] == "bauen":
        n = bauen(argv[2])
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
        kdatei = os.path.join(WURZEL, "..", "kernel", "net", "netmark.fi")
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
