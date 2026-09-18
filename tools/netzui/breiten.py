#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/netzui/breiten.py -- RUNDE O-NETZUI: PASSEN DIE TEXTE IN DIE SPALTE?

    python3 tools/netzui/breiten.py [locale/de/messages ...]

============================ WARUM ES DAS GIBT ============================

Die Netzseite der Einstellungen hat zwei Spalten: links 300 Bildpunkte
fuer Zustand und Anschrift, rechts 460 fuer die beiden Tafeln. Ein Text
der linken Spalte, der breiter als 284 Punkte wird (300 minus 16 Einzug),
laeuft in die rechte hinein -- er ueberdeckt die Tafel und sieht aus wie
ein Fehler im Fensterserver.

GENAU DAS IST IN DIESER RUNDE PASSIERT, und es ist nicht im Quelltext
aufgefallen, sondern in der Bildkontrolle: auf der seriellen Leitung
stand

    wlib: text ... tw=291 t=Status: disconnected (no cable/carrier)
    wlib: text ... tw=372 t=Link speed: unknown (the card does not report it)

-- 291 und 372 Punkte in einer Spalte, die 284 hat. Die zwei Saetze
waren als Erklaerung gedacht und gut gemeint; sie gehoeren in die
Fussnote unter den Tafeln, wo 428 Punkte Platz sind.

DIE BREITE WIRD GERECHNET UND NICHT GERATEN. Aus derselben Messung:
"Status: disconnected (no cable/carrier)" sind 38 Zeichen und 291 Punkte,
also 7,66 Punkte je Zeichen in der Schrift dieses Systems bei einfacher
Vervielfachung. Das ist eine Naeherung -- ein `i` ist schmaler als ein
`W` --, und sie ist absichtlich GROSSZUEGIG: wer damit durchkommt, kommt
auch in Wirklichkeit durch.

GEPRUEFT WIRD DER SCHLIMMSTE FALL UND NICHT DER RUHEZUSTAND. "9 KiB/s"
passt immer; die Frage ist, ob "1023,9 MiB/s" auch noch passt. Deshalb
setzt dieses Skript in jede Zeile die laengstmoeglichen Werte ein, die
die Formatierung in settings.fi erzeugen kann.
"""
import sys
import re

# Gemessen an `wlib: text ... tw=`, siehe Kopf.
PPC = 291 / 38
# Die linke Spalte: 300 Punkte breit, der Text faengt bei 16 an.
LINKS = 300 - 16
# Die Fussnote steht in der rechten Spalte (460 breit, Einzug 16).
RECHTS = 460 - 16

# Die laengsten Werte, die die Formatierung erzeugen kann.
# `rate_an` endet bei "1023,9 GiB/s", `menge_an` bei "1023,9 GiB",
# `mbit_an` bei "1000 Mbit/s" bzw. dem Wort fuer unbekannt.
WERTE = {
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

    # Jede Zeile der linken Spalte im schlimmsten Fall.
    zeilen = []
    for z in ("connected", "disconnected", "noaddr", "noroute"):
        zeilen.append(("Zustand/" + z, g("heading") + g(z), LINKS))
    zeilen.append(("Verbindungsrate/unbekannt",
                   g("linkspeed") + g("unknown"), LINKS))
    zeilen.append(("Verbindungsrate/Zahl",
                   g("linkspeed") + WERTE["mbit"], LINKS))
    zeilen.append(("Empfang", g("down") + WERTE["rate"], LINKS))
    zeilen.append(("Senden", g("up") + WERTE["rate"], LINKS))
    zeilen.append(("Gesamt",
                   g("total") + WERTE["menge"] + " / " + WERTE["menge"], LINKS))
    for z in ("rttnone", "rttwait"):
        zeilen.append(("Antwortzeit/" + z, g("rtt") + g(z), LINKS))
    zeilen.append(("Antwortzeit/Zahl", g("rtt") + WERTE["ms"], LINKS))
    # Und die Fussnote in der rechten Spalte.
    zeilen.append(("Fussnote", g("note"), RECHTS))

    schlecht = 0
    for name, text, grenze in zeilen:
        w = breite(text)
        zustand = "ok      "
        if w > grenze:
            zustand = "ZU BREIT"
            schlecht += 1
        print("  %s %4d/%d  %-26s %s" % (zustand, w, grenze, name, text))
    return schlecht

def main():
    pfade = sys.argv[1:] or ["locale/de/messages", "locale/en/messages"]
    schlecht = 0
    for p in pfade:
        print("== %s ==" % p)
        schlecht += pruef(p)
    print()
    if schlecht:
        print("BREITEN: %d Zeile(n) laufen aus ihrer Spalte" % schlecht)
        return 1
    print("BREITEN: alle Zeilen passen in ihre Spalte")
    return 0

if __name__ == "__main__":
    sys.exit(main())
