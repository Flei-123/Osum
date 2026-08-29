#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/paint/scalars.py -- ZWEI RUNDEN AUF DERSELBEN ADRESSE.
#
# WARUM ES DIESES SKRIPT GIBT.  Runde PAINT wollte in `kernel/wm.fi` drei
# Woerter fuer die Fensterform ablegen und suchte dafuer einen freien
# Versatz.  Dabei fiel auf, dass zwei laengst gemergte Runden bereits
# uebereinanderliegen:
#
#     const S_TILE: u64 = 0x180      // Runde TILING
#     const S_DECO: u64 = 0x180      // Runde THEME, elf Woerter
#
# Beide werden ueber dasselbe `gs`/`ss` gelesen und geschrieben, beide
# im selben Block (`kstate.WM_OFF`).  Das ist derselbe Fehler wie in
# Runde K7B, wo der Zeichensatz und die Signaltafel auf 0x2F000 lagen:
# jeder Zweig fuer sich gruen, keine gemeinsame ZEILE, nur eine
# gemeinsame ADRESSE -- und deshalb sieht ein Textverschmelzer ihn nicht.
#
# `tools/kernel/memmap.py` prueft die grossen Bereiche von `kdata`
# gegeneinander.  Dieses Skript geht eine Ebene tiefer: die SKALARE
# INNERHALB eines Bereichs.  Die Regel, an die sich dieser Baum haelt,
# lautet: in EINER Datei gehoeren alle `const S_<NAME>` in denselben
# Skalarblock.  Also duerfen sich in einer Datei keine zwei davon
# ueberschneiden.
#
#   ./tools/paint/scalars.py [dateien...]
#
# Ohne Argumente werden kernel/*.fi geprueft.  Beendigungscode 0 = keine
# Ueberschneidung.
#
# WIE DIE LAENGE EINES EINTRAGS BESTIMMT WIRD.  Ein Skalar ist acht
# Oktette lang, ausser der Kommentar dahinter sagt etwas anderes: die
# Form "N Woerter" oder "N Oktette" wird gelesen.  Steht daneben eine
# eigene Laengenkonstante (`DECO_SLOTS`), wird sie ebenfalls benutzt --
# genau das ist der Fall, an dem `S_DECON` in diesem Baum haengt.
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.normpath(os.path.join(HIER, "..", ".."))

# NUR HEXADEZIMALE VIELFACHE VON ACHT GELTEN ALS VERSATZ.  Das ist keine
# Formalie: `kernel/sched.fi` schreibt `const S_FREE: u64 = 0`,
# `S_READY = 1`, `S_RUN = 2` -- das sind ZUSTAENDE einer Aufgabe und
# keine Adressen, und `kernel/ansi.fi` und `kernel/netmon.fi` tun
# dasselbe mit Zustaenden und Feldnummern.  Ein Pruefer, der die
# mitzaehlt, meldet sechsundneunzig Ueberschneidungen, von denen
# vierundneunzig keine sind -- und wird dann abgeschaltet.  Die Regel
# dieses Baums ist eindeutig: ein Versatz steht hexadezimal und ist
# durch acht teilbar.
CONST = re.compile(
    r"^const\s+(S_[A-Z0-9_]+)\s*:\s*u64\s*=\s*(0x[0-9A-Fa-f]+)\s*(//.*)?$")
ZAHL = re.compile(
    r"^const\s+([A-Z0-9_]+)\s*:\s*u64\s*=\s*(0x[0-9A-Fa-f]+|\d+)", re.M)
WOERTER = re.compile(r"(\d+)\s+W[oe]+rter")
OKTETTE = re.compile(r"(\d+)\s+Oktette")

# Was ein Eintrag ausdruecklich belegt, wenn der Kommentar es nicht
# sagt.  Hier stehen nur Faelle, in denen eine LAENGENKONSTANTE danebenm
# liegt und der Kommentar sie nicht wiederholt.
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
            print("  FAIL  %s: %s (0x%X, %d Oktette, Zeile %d) und "
                  "%s (0x%X, %d Oktette, Zeile %d) ueberschneiden sich"
                  % (rel, an, aw, al, az, bn, bw, bl, bz))
    print("PAINT-SKALARE: %d Skalare in %d Dateien, %d Ueberschneidungen"
          % (gesamt, len(dateien), schlecht))
    if schlecht == 0:
        print("  OK    keine zwei Skalare einer Datei liegen aufeinander")
    return 1 if schlecht else 0


if __name__ == "__main__":
    sys.exit(main())
