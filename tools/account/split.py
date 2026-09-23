#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/account/split.py -- RUNDE KONTO: DIE TRENNUNGSWACHE.

Die Zusage lautet: ANBIETERWISSEN BLEIBT IM RUECKEN. Sobald irgendwo im
allgemeinen Teil `wenn anbieter == "..."` steht, ist die Trennung kaputt
-- und niemand merkt es, weil so ein `wenn` funktioniert.

Also wird es gemessen. Dieses Skript liest die allgemeinen Dateien und
sucht darin nach den Namen der Ruecken. Gefunden wird nichts -- ausser
in der EINEN Anmeldeliste in `konto.fi`, die es geben muss, damit ein
Ruecken ueberhaupt in die Tafel kommt.

    split.py <wurzel>            prueft und meldet
    split.py <wurzel> --zahlen   nur die Zahlen, fuer den Laeufer

Rueckgabe 0, wenn die Trennung haelt, sonst 1.
"""
import os
import re
import sys

# Die allgemeinen Dateien: sie duerfen von keinem Anbieter wissen.
ALLGEMEIN = [
    "kernel/app/anbieter.fi",
    "kernel/app/knetz.fi",
    "kernel/app/kspeicher.fi",
    "kernel/app/ksiegel.fi",
    "kernel/app/kjson.fi",
    "kernel/app/kmsg.fi",
    "kernel/app/kgegen.fi",
    "kernel/app/account.fi",
]

# Die Ruecken. Ihr Name IST das Anbieterwissen.
RUECKEN = ["kernel/app/anb_jarvis.fi", "kernel/app/anb_xoffi.fi",
           "kernel/app/anb_eigen.fi"]

# Die Woerter, nach denen gesucht wird -- die Namen der Ruecken, plus
# die Marken, unter denen sie im Netz auftreten.
WOERTER = ["xoffi", "jarvis", "fleitec", "nexus"]

# Die EINE Liste, in der die Ruecken angemeldet werden. Zeilen zwischen
# diesen beiden Marken duerfen Anbieternamen tragen; sonst keine.
MARKE_AUF = "fn push_login"   # vor Runde ENGLISCH: ruecken_anmelden
MARKE_ZU = "^}"


def zeilen_der_anmeldung(text):
    """Die Zeilennummern (1-basiert) der Anmeldefunktion."""
    zeilen = text.split("\n")
    drin = False
    raus = set()
    for i, z in enumerate(zeilen, 1):
        if z.startswith(MARKE_AUF):
            drin = True
        if drin:
            raus.add(i)
        if drin and re.match(MARKE_ZU, z):
            drin = False
    return raus


def kommentarfrei(zeile):
    """Ein Kommentar darf einen Anbieter NENNEN -- er kann nichts tun.

    Das ist keine Bequemlichkeit: `anbieter.fi` muss erklaeren duerfen,
    warum es keinen Anbieter kennt, und `konto.fi` muss die Ausnahme
    begruenden duerfen. Was gesucht wird, ist WIRKENDER Quelltext.
    """
    i = zeile.find("//")
    return zeile if i < 0 else zeile[:i]


def pruefe(wurzel):
    verstoesse = []
    geprueft = 0
    for rel in ALLGEMEIN:
        pfad = os.path.join(wurzel, rel)
        if not os.path.exists(pfad):
            verstoesse.append((rel, 0, "die Datei fehlt"))
            continue
        text = open(pfad, encoding="utf-8").read()
        erlaubt = zeilen_der_anmeldung(text) if rel.endswith(("konto.fi", "account.fi")) \
            else set()
        for nr, zeile in enumerate(text.split("\n"), 1):
            geprueft += 1
            if nr in erlaubt:
                continue
            code = kommentarfrei(zeile).lower()
            # EINE EINFUHR IST KEINE ENTSCHEIDUNG. `import anb_xoffi`
            # sagt, dass es den Ruecken gibt; es sagt nichts darueber,
            # was er ist, und es kann sich nicht verzweigen. Was diese
            # Wache sucht, ist ein `if`, ein Vergleich, ein Sonderweg.
            if code.strip().startswith("import "):
                continue
            for w in WOERTER:
                if w in code:
                    verstoesse.append((rel, nr, w))
    return verstoesse, geprueft


def ruecken_zahlen(wurzel):
    """Wie viel Anbieterwissen wirklich in den Ruecken steckt."""
    aus = []
    for rel in RUECKEN:
        pfad = os.path.join(wurzel, rel)
        if not os.path.exists(pfad):
            continue
        text = open(pfad, encoding="utf-8").read()
        n = 0
        for zeile in text.split("\n"):
            code = kommentarfrei(zeile).lower()
            for w in WOERTER:
                if w in code:
                    n += 1
                    break
        aus.append((rel, len(text.split("\n")), n))
    return aus


def main():
    if len(sys.argv) < 2:
        print("split.py <wurzel> [--zahlen]")
        return 2
    wurzel = sys.argv[1]
    zahlen = "--zahlen" in sys.argv
    verstoesse, geprueft = pruefe(wurzel)
    if zahlen:
        print("geprueft=%d dateien=%d verstoesse=%d"
              % (geprueft, len(ALLGEMEIN), len(verstoesse)))
        for rel, n, k in ruecken_zahlen(wurzel):
            print("ruecken %s zeilen=%d anbieterzeilen=%d" % (rel, n, k))
    for rel, nr, w in verstoesse:
        print("VERSTOSS %s:%d -- '%s' im allgemeinen Teil" % (rel, nr, w))
    return 1 if verstoesse else 0


if __name__ == "__main__":
    sys.exit(main())
