#!/usr/bin/env python3
"""tools/netview/icons.py -- die Symbole der Runde NETVIEW, aus EINER Quelle.

Der Nachtrag der Runde verlangt zwei Anzeigen, und sie werden an ZWEI
Stellen gemalt, die nichts miteinander zu tun haben:

  * die Taskleiste (`kernel/user/leiste.fi`) -- Ring 3, malt eine
    OSYM-Datei von der Platte,
  * die Titelleiste (`kernel/wm.fi`) -- der KERN, der keine Datei von der
    Platte liest, waehrend er ein Fenster zeichnet.

Zwei Stellen, ein Zeichen. Der bequeme Weg waere, die zwoelf mal zwoelf
Bildpunkte zweimal hinzuschreiben; das ist genau die Sorte Verdopplung,
die einen Monat spaeter zwei verschiedene Zeichen fuer dieselbe Sache
ergibt. Also: die ZEICHNUNG unter `assets/netview/*.txt` ist die Quelle,
und dieses Werkzeug macht daraus

  1. die OSYM-Dateien fuer die Platte (ueber `tools/k15/symbol.py`,
     dasselbe Format wie jedes Buendelsymbol -- kein zweites),
  2. `kernel/netmark.fi`, den Kern-Teil: dieselben Zeichen als
     Bitreihen, damit `wm.fi` sie ohne Dateisystem malen kann.

UND ES PRUEFT SICH SELBST. `icons.py --pruefe` baut alles noch einmal und
vergleicht es mit dem, was im Baum liegt. Weicht `kernel/netmark.fi` von
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
    icons.py kern   <kernel/netmark.fi>
    icons.py pruefe [--kern kernel/netmark.fi]
"""

import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
sys.path.insert(0, os.path.join(WURZEL, "k15"))
import symbol as symmod  # noqa: E402

QUELLE = os.path.join(WURZEL, "..", "assets", "netview")

# Die vier Systemzustaende, in der Reihenfolge, in der der Kern sie
# zaehlt (`sys.NS_*`), und die drei Merkmale in der Reihenfolge der
# Sichten (`netview.V_*`, ohne `real`, das keines bekommt).
ZUSTAENDE = ["state-nocarrier", "state-noip", "state-noroute", "state-online"]
MERKMALE = ["mark-filtered", "mark-faked", "mark-none"]

# DIE ZWEI SCHEMEN, GEGEN DIE GERECHNET WIRD -- AUS DEN DATEIEN, mit
# denen die gemessenen Laeufe wirklich booten
# (`assets/netview/theme-dark`, `theme-light`). Sie standen hier erst als
# Zahlen im Quelltext; das waere eine zweite Fassung derselben Farben
# gewesen, und die erste Aenderung an einer der Dateien haette diese
# Pruefung zu einer Aussage ueber nichts gemacht.
#
# Der Name der Rolle ist der Name des Schluessels in der Datei, mit
# einer Ausnahme: `ink` heisst dort `fg`, weil die Datei die Namen der
# Runde K15 traegt und die nicht dieser Runde gehoren.
DATEI_NAME = {"ink": "fg", "dim": "dim", "accent": "accent",
              "warn": "focus", "panel": "panel"}


def schema_lesen(pfad):
    werte = {}
    for roh in open(pfad, encoding="ascii"):
        roh = roh.strip()
        if not roh or roh.startswith("#") or "=" not in roh:
            continue
        k, _, v = roh.partition("=")
        werte[k.strip()] = int(v.strip(), 16)
    aus = {}
    for rolle, schluessel in DATEI_NAME.items():
        if schluessel not in werte:
            raise SystemExit("icons: %s hat kein %s=" % (pfad, schluessel))
        aus[rolle] = werte[schluessel]
    return aus


SCHEMEN = {
    "dark": schema_lesen(os.path.join(QUELLE, "theme-dark")),
    "light": schema_lesen(os.path.join(QUELLE, "theme-light")),
}

MIN_KONTRAST = 4.5
MIN_UNTERSCHIED = 33  # Prozent der eingefaerbten Bildpunkte


# ------------------------------------------------------------ Kontrast

def linear(k):
    k = k / 255.0
    if k <= 0.03928:
        return k / 12.92
    return ((k + 0.055) / 1.055) ** 2.4


def helligkeit(rgb):
    r, g, b = (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)


def kontrast(a, b):
    la, lb = helligkeit(a), helligkeit(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


# ------------------------------------------------------------ die Bilder

def zeichnung(name):
    return os.path.join(QUELLE, name + ".txt")


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


# ------------------------------------------------------------ die Pruefung

def pruefe_gestaltung(sagen=True):
    fehler = 0

    def sag(t):
        if sagen:
            print(t)

    sag("== Kontrast jeder Rolle gegen die Flaeche, hell und dunkel ==")
    for sn, s in sorted(SCHEMEN.items()):
        for rolle in ("ink", "dim", "accent", "warn"):
            k = kontrast(s[rolle], s["panel"])
            gut = k >= MIN_KONTRAST
            fehler += 0 if gut else 1
            sag("  %-5s %-7s %5.2f:1  %s"
                % (sn, rolle, k, "ok" if gut else "ZU WENIG"))

    for titel, gruppe in (("Systemzustand", ZUSTAENDE), ("Merkmal", MERKMALE)):
        sag("== %s: FORM VOR FARBE -- Schattenrisse gegeneinander ==" % titel)
        risse = {n: schattenriss(n) for n in gruppe}
        for i in range(len(gruppe)):
            for j in range(i + 1, len(gruppe)):
                a, wa, ha = risse[gruppe[i]]
                b, wb, hb = risse[gruppe[j]]
                if (wa, ha) != (wb, hb):
                    sag("  %s und %s sind nicht gleich gross" % (gruppe[i], gruppe[j]))
                    fehler += 1
                    continue
                u = len(a | b)
                d = len(a ^ b)
                pz = 100 * d // u if u else 0
                gut = pz >= MIN_UNTERSCHIED
                fehler += 0 if gut else 1
                sag("  %-15s vs %-15s %3d von %3d = %2d%%  %s"
                    % (gruppe[i].split("-", 1)[1], gruppe[j].split("-", 1)[1], d, u, pz,
                       "ok" if gut else "ZU AEHNLICH"))
    return fehler


def masse():
    """Groesse und Deckung je Zeichen -- die Zahlen fuer die Doku."""
    aus = []
    for n in ZUSTAENDE + MERKMALE:
        riss, w, h = schattenriss(n)
        aus.append((n, w, h, len(riss), w * h))
    return aus


# ------------------------------------------------------------ das Erzeugen

KOPF = """// kernel/netmark.fi -- ERZEUGT AUS assets/netview/mark-*.txt.
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

    def tafel(index):
        t = []
        for m, r in enumerate(reihen):
            for y, paar in enumerate(r):
                if paar[index] == 0:
                    continue
                t.append("    if m == %d && y == %d {\n        return 0x%X\n    }\n"
                         % (m, y, paar[index]))
        return "".join(t)

    return KOPF % {
        "w": w, "h": h, "count": len(MERKMALE),
        "masken": tafel(0), "rollen": tafel(1),
    }


def bauen(ziel):
    os.makedirs(ziel, exist_ok=True)
    n = 0
    for name in ZUSTAENDE + MERKMALE:
        d = symmod.baue(zeichnung(name))
        with open(os.path.join(ziel, name), "wb") as f:
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
        for n, w, h, deck, ganz in masse():
            print("%-18s %2dx%-2d  %3d von %3d eingefaerbt = %d%%"
                  % (n, w, h, deck, ganz, 100 * deck // ganz))
        return 0
    if len(argv) >= 2 and argv[1] == "pruefe":
        fehler = pruefe_gestaltung()
        kdatei = os.path.join(WURZEL, "..", "kernel", "netmark.fi")
        if "--kern" in argv:
            kdatei = argv[argv.index("--kern") + 1]
        soll = kernquelle()
        try:
            ist = open(kdatei, encoding="ascii").read()
        except OSError:
            ist = None
        if ist is None:
            print("== %s fehlt ==" % kdatei)
            fehler += 1
        elif ist != soll:
            print("== %s weicht von der Zeichnung ab ==" % kdatei)
            fehler += 1
        else:
            print("== %s stimmt Oktett fuer Oktett mit der Zeichnung ==" % kdatei)
        print("icons: %d Beanstandungen" % fehler)
        return 1 if fehler else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
