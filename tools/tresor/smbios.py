#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tresor/smbios.py -- SMBIOS, ZUM ZWEITEN MAL gelesen.

    smbios.py <speicherabzug.bin>            die Felder, als schluessel=wert
    smbios.py --koeder <speicherabzug.bin>   der Beleg fuer die Pruefsumme

Das ist die zweite Umsetzung des Lesers in `kernel/hwid.fi`, geschrieben
aus der Beschreibung und NICHT aus dem Firn-Quelltext. Genau das ist der
Sinn: zwei Programme, in zwei Sprachen, auf zwei Seiten eines
Speicherabzugs. Eine Umsetzung allein kann zweimal denselben Fehler
machen und niemand merkt es -- die Zahlen sehen ja plausibel aus.

DIE ZEICHENKETTENREGEL (SMBIOS 6.1.3) ist die Stelle, an der beide
Umsetzungen unabhaengig voneinander richtig liegen muessen: hinter dem
Rumpf von `length` Oktetten folgt je Zeichenkette eine NUL, und der Satz
endet mit EINER ZUSAETZLICHEN NUL. Nur wenn es gar keine Zeichenkette
gibt, stehen dort genau zwei NUL.

Die naheliegende Lesart "der Satz endet bei zwei Nullen hintereinander"
ist falsch, und sie faellt nicht sofort auf: sie liest die erste Struktur
richtig und haelt danach das Typ-Oktett der naechsten (eine 1, keine 0)
fuer eine Fortsetzung. Gemessen: EINE Struktur von neun.
"""
import struct
import sys


def einstiegspunkte(d):
    """Alle Einstiegspunkte, die 16-ausgerichtet sind UND deren Pruefsumme
    aufgeht. Beide Bedingungen sind noetig; siehe --koeder."""
    treffer = []
    for at in range(0, len(d) - 32, 16):
        if d[at:at + 5] == b"_SM3_":
            ln = d[at + 6]
            if ln and at + ln <= len(d) and sum(d[at:at + ln]) % 256 == 0:
                treffer.append(("_SM3_", at, ln))
        elif d[at:at + 4] == b"_SM_":
            ln = d[at + 5]
            if ln and at + ln <= len(d) and sum(d[at:at + ln]) % 256 == 0:
                treffer.append(("_SM_", at, ln))
    return treffer


def strukturen(tbl):
    p = 0
    while p + 4 <= len(tbl):
        t, l = tbl[p], tbl[p + 1]
        if l < 4:
            return
        rumpf = tbl[p:p + l]
        q = p + l
        texte = []
        if q + 1 < len(tbl) and tbl[q] == 0 and tbl[q + 1] == 0:
            q += 2                       # gar keine Zeichenkette
        else:
            while q < len(tbl):
                e = tbl.find(b"\0", q)
                if e < 0:
                    q = len(tbl)
                    break
                texte.append(tbl[q:e].decode("latin1"))
                q = e + 1
                if q < len(tbl) and tbl[q] == 0:
                    q += 1               # die zusaetzliche NUL schliesst
                    break
        yield t, rumpf, texte
        if t == 127:
            return
        p = q


def koeder(d):
    """Der Beleg, dass die Pruefsumme gebraucht wird: irgendwo steht die
    ZEICHENKETTE '_SM3_' (SeaBIOS baut den Einstiegspunkt daraus), und sie
    ist keiner."""
    at = d.find(b"_SM3_")
    if at < 0:
        print("koeder=0")
        return 0
    ln = d[at + 6] if at + 6 < len(d) else 0
    gut = bool(ln) and at + ln <= len(d) and sum(d[at:at + ln]) % 256 == 0
    print("koeder=1")
    print("koeder_adresse=0x%x" % at)
    print("koeder_ausgerichtet=%s" % ("ja" if at % 16 == 0 else "nein"))
    print("koeder_pruefsumme=%s" % ("stimmt" if gut else "falsch"))
    return 0


def main(argv):
    if len(argv) > 1 and argv[1] == "--koeder":
        return koeder(open(argv[2], "rb").read())
    if len(argv) < 2:
        print(__doc__)
        return 2
    d = open(argv[1], "rb").read()

    treffer = einstiegspunkte(d)
    if not treffer:
        print("kein gueltiger Einstiegspunkt")
        return 1
    # Wie im Kernel: SMBIOS 3 hat Vorrang vor SMBIOS 2.
    treffer.sort(key=lambda x: 3 if x[0] == "_SM3_" else 2)
    art, at, _ = treffer[-1]

    if art == "_SM_":
        haupt, neben = d[at + 6], d[at + 7]
        tlen = struct.unpack_from("<H", d, at + 0x16)[0]
        tadr = struct.unpack_from("<I", d, at + 0x18)[0]
        kind = 2
    else:
        haupt, neben = d[at + 7], d[at + 8]
        tlen = struct.unpack_from("<I", d, at + 0x0C)[0]
        tadr = struct.unpack_from("<Q", d, at + 0x10)[0]
        kind = 3

    print("entry=0x%x" % at)
    print("kind=%d" % kind)
    print("version=%d" % (haupt * 100 + neben))
    print("table=0x%x" % tadr)
    print("tlen=%d" % tlen)

    tbl = d[tadr:tadr + tlen]
    felder = {}
    n = 0
    for t, rumpf, texte in strukturen(tbl):
        n += 1

        def s(i):
            return texte[i - 1] if 1 <= i <= len(texte) else ""

        if t == 1:
            felder["sys_man"] = s(rumpf[4])
            felder["sys_prod"] = s(rumpf[5])
            felder["sys_ver"] = s(rumpf[6])
            felder["sys_ser"] = s(rumpf[7])
            if len(rumpf) >= 24:
                felder["uuid"] = rumpf[8:24].hex()
        elif t == 2:
            felder["brd_man"] = s(rumpf[4])
            felder["brd_prod"] = s(rumpf[5])
            felder["brd_ser"] = s(rumpf[7])
    print("count=%d" % n)
    # Leere Felder wie der Kernel schreiben, damit sich beide vergleichen
    # lassen, ohne dass ein Skript die Faelle auseinanderhalten muss.
    for k in ("sys_man", "sys_prod", "sys_ver", "sys_ser",
              "brd_man", "brd_prod", "brd_ser"):
        v = felder.get(k, "")
        print("%s=%s" % (k, v if v else "(empty)"))
    print("uuid=%s" % felder.get("uuid", "00" * 16))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
