#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/alltag/rechner.py -- DER RECHNER DES WIRTS, ZUM VERGLEICHEN.

    rechner.py liste                 die Ausdruecke, einer je Zeile
    rechner.py skript <ziel>         das Shell-Skript fuer den Gast
    rechner.py pruefen <serial.txt>  Gast gegen Python, Zeile fuer Zeile

Es ist ABSICHT, dass hier Python rechnet und nicht ein zweites Mal
derselbe Zerteiler: eine Zusage, die gegen sich selbst geprueft wird,
ist keine. Uebersetzt wird nur die Schreibweise -- `^` zu `**`, `n!` zu
`factorial(n)`, `ln` zu `log`, `log` zu `log10` --, gerechnet wird mit
der Bibliothek des Wirts.

Verglichen wird mit einer RELATIVEN Schranke von 1e-9. Der Gast druckt
zwoelf geltende Ziffern, und seine `exp`/`ln`/`sin` sind Naeherungen in
Firn; auf zwoelf Stellen genau zu sein ist die Zusage, auf sechzehn
waere geflunkert.
"""
import math
import re
import sys

SCHRANKE = 1e-9
QUELLE = "tools/alltag/ausdruecke.txt"

UMGEBUNG = {
    "sqrt": math.sqrt, "abs": abs, "sin": math.sin, "cos": math.cos,
    "tan": math.tan, "asin": math.asin, "acos": math.acos,
    "atan": math.atan, "ln": math.log, "log": math.log10,
    "log2": math.log2, "exp": math.exp, "floor": math.floor,
    "ceil": math.ceil, "round": round, "cbrt": lambda x: math.copysign(
        abs(x) ** (1.0 / 3.0), x),
    "pow": lambda a, b: a ** b, "min": min, "max": max,
    "hypot": math.hypot, "atan2": math.atan2, "fmod": math.fmod,
    "factorial": lambda n: float(math.factorial(int(n))),
    "pi": math.pi, "e": math.e,
}


def ausdruecke():
    aus = []
    for z in open(QUELLE, encoding="utf-8"):
        z = z.strip()
        if z and not z.startswith("#"):
            aus.append(z)
    return aus


def nach_python(a: str) -> str:
    p = a.replace("^", "**")
    # `n!` -- die Fakultaet steht hinter ihrem Wert, in Python davor.
    while True:
        m = re.search(r"(\d+(?:\.\d+)?|\))\s*!", p)
        if not m:
            break
        if m.group(1) == ")":
            tiefe = 0
            i = m.end() - 2
            while i >= 0:
                if p[i] == ")":
                    tiefe += 1
                elif p[i] == "(":
                    tiefe -= 1
                    if tiefe == 0:
                        break
                i -= 1
            p = p[:i] + "factorial(" + p[i:m.end() - 1] + ")" + p[m.end():]
        else:
            p = (p[:m.start()] + "factorial(" + m.group(1) + ")"
                 + p[m.end():])
    return p


def wert(a: str) -> float:
    return float(eval(nach_python(a), {"__builtins__": {}}, UMGEBUNG))


def gleich(gast: float, wirt: float) -> bool:
    if math.isnan(gast) or math.isnan(wirt):
        return False
    d = abs(gast - wirt)
    if d == 0.0:
        return True
    return d <= SCHRANKE * max(1.0, abs(wirt))


def skript(ziel: str) -> int:
    zeilen = ["# von tools/alltag/rechner.py erzeugt"]
    for i, a in enumerate(ausdruecke()):
        zeilen.append("echo AUSDRUCK-%d" % i)
        zeilen.append("calc -e %s" % a)
    zeilen.append("echo AUSDRUECKE-FERTIG")
    open(ziel, "w", encoding="utf-8").write("\n".join(zeilen) + "\n")
    print("%d Ausdruecke nach %s" % (len(ausdruecke()), ziel))
    return 0


def pruefen(serial: str) -> int:
    text = open(serial, "rb").read().decode("utf-8", "replace")
    zeilen = text.split("\n")
    aus = ausdruecke()
    gut = 0
    schlecht = 0
    for i, a in enumerate(aus):
        marke = "AUSDRUCK-%d" % i
        antwort = None
        for k, z in enumerate(zeilen):
            if z.strip() == marke:
                for j in range(k + 1, min(k + 12, len(zeilen))):
                    s = zeilen[j].strip()
                    if not s or s.startswith("elf:") or s.startswith("osum$"):
                        continue
                    antwort = s
                    break
                break
        soll = wert(a)
        if antwort is None:
            print("  FAIL  %-22s keine Antwort im Gast (soll %.12g)"
                  % (a, soll))
            schlecht += 1
            continue
        try:
            ist = float(antwort)
        except ValueError:
            print("  FAIL  %-22s Gast sagt '%s' (soll %.12g)"
                  % (a, antwort, soll))
            schlecht += 1
            continue
        if gleich(ist, soll):
            print("  OK    %-22s %s" % (a, antwort))
            gut += 1
        else:
            print("  FAIL  %-22s Gast %s, Python %.12g" % (a, antwort, soll))
            schlecht += 1
    print("rechner: %d von %d stimmen mit Python ueberein" % (gut, len(aus)))
    return 0 if schlecht == 0 else 1


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    if argv[1] == "liste":
        for a in ausdruecke():
            print(a)
        return 0
    if argv[1] == "skript" and len(argv) > 2:
        return skript(argv[2])
    if argv[1] == "pruefen" and len(argv) > 2:
        return pruefen(argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
