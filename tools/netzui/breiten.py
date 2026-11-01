#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys
import re

PPC = 291 / 38
LEFT = 300 - 16
RIGHT = 460 - 16

VALUES = {
    "rate": "1023,9 GiB/s",
    "menge": "1023,9 GiB",
    "mbit": "1000 Mbit/s",
    "ms": "1234 ms",
}

def breite(s):
    return round(len(s) * PPC)

def lies(pfad):
    aus = {}
    with open(pfad, encoding="utf-8") as f:
        for z in f:
            m = re.match(r"^(settings\.net\.[a-z.]+) = (.*)$", z.rstrip("\n"))
            if m:
                aus[m.group(1)] = m.group(2)
    return aus

def pruef(pfad):
    k = lies(pfad)
    fehlt = [n for n in ("heading", "linkspeed", "down", "up", "total",
                         "rtt", "unknown", "connected", "disconnected",
                         "noaddr", "noroute", "rttnone", "rttwait", "note")
             if "settings.net." + n not in k]
    if fehlt:
        print("  FEHLENDE SCHLUESSEL: %s" % ", ".join(fehlt))
        return 1

    def g(n):
        return k["settings.net." + n]

    zeilen = []
    for z in ("connected", "disconnected", "noaddr", "noroute"):
        zeilen.append(("Zustand/" + z, g("heading") + g(z), LEFT))
    zeilen.append(("Verbindungsrate/unbekannt",
                   g("linkspeed") + g("unknown"), LEFT))
    zeilen.append(("Verbindungsrate/Zahl",
                   g("linkspeed") + VALUES["mbit"], LEFT))
    zeilen.append(("Empfang", g("down") + VALUES["rate"], LEFT))
    zeilen.append(("Senden", g("up") + VALUES["rate"], LEFT))
    zeilen.append(("Gesamt",
                   g("total") + VALUES["menge"] + " / " + VALUES["menge"], LEFT))
    for z in ("rttnone", "rttwait"):
        zeilen.append(("Antwortzeit/" + z, g("rtt") + g(z), LEFT))
    zeilen.append(("Antwortzeit/Zahl", g("rtt") + VALUES["ms"], LEFT))
    zeilen.append(("Fussnote", g("note"), RIGHT))

    schlecht = 0
    for name, text, limit in zeilen:
        w = breite(text)
        state = "ok      "
        if w > limit:
            state = "ZU BREIT"
            schlecht += 1
        print("  %s %4d/%d  %-26s %s" % (state, w, limit, name, text))
    return schlecht

def main():
    pfade = sys.argv[1:] or ["locale/de/messages", "locale/en/messages"]
    schlecht = 0
    for p in pfade:
        print("== %s ==" % p)
        schlecht += pruef(p)
    print()
    if schlecht:
        print("WIDTHS: %d row(s) overflow their column" % schlecht)
        return 1
    print("WIDTHS: all rows fit their column")
    return 0

if __name__ == "__main__":
    sys.exit(main())
