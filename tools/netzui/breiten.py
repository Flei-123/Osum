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

def width(s):
    return round(len(s) * PPC)

def read(path):
    aus = {}
    with open(path, encoding="utf-8") as f:
        for z in f:
            m = re.match(r"^(settings\.net\.[a-z.]+) = (.*)$", z.rstrip("\n"))
            if m:
                aus[m.group(1)] = m.group(2)
    return aus

def check(path):
    k = read(path)
    missing = [n for n in ("heading", "linkspeed", "down", "up", "total",
                         "rtt", "unknown", "connected", "disconnected",
                         "noaddr", "noroute", "rttnone", "rttwait", "note")
             if "settings.net." + n not in k]
    if missing:
        print("  FEHLENDE SCHLUESSEL: %s" % ", ".join(missing))
        return 1

    def g(n):
        return k["settings.net." + n]

    lines = []
    for z in ("connected", "disconnected", "noaddr", "noroute"):
        lines.append(("Zustand/" + z, g("heading") + g(z), LEFT))
    lines.append(("Verbindungsrate/unbekannt",
                   g("linkspeed") + g("unknown"), LEFT))
    lines.append(("Verbindungsrate/Zahl",
                   g("linkspeed") + VALUES["mbit"], LEFT))
    lines.append(("Empfang", g("down") + VALUES["rate"], LEFT))
    lines.append(("Senden", g("up") + VALUES["rate"], LEFT))
    lines.append(("Gesamt",
                   g("total") + VALUES["menge"] + " / " + VALUES["menge"], LEFT))
    for z in ("rttnone", "rttwait"):
        lines.append(("Antwortzeit/" + z, g("rtt") + g(z), LEFT))
    lines.append(("Antwortzeit/Zahl", g("rtt") + VALUES["ms"], LEFT))
    lines.append(("Fussnote", g("note"), RIGHT))

    bad = 0
    for name, text, limit in lines:
        w = width(text)
        state = "ok      "
        if w > limit:
            state = "ZU BREIT"
            bad += 1
        print("  %s %4d/%d  %-26s %s" % (state, w, limit, name, text))
    return bad

def main():
    pfade = sys.argv[1:] or ["locale/de/messages", "locale/en/messages"]
    bad = 0
    for p in pfade:
        print("== %s ==" % p)
        bad += check(p)
    print()
    if bad:
        print("WIDTHS: %d row(s) overflow their column" % bad)
        return 1
    print("WIDTHS: all rows fit their column")
    return 0

if __name__ == "__main__":
    sys.exit(main())
