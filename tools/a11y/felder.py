#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/a11y/felder.py -- DIE PACKUNG STEHT AN ZWEI STELLEN. SIND SIE GLEICH?

Der Satz eines Baumknotens ist in `kernel/ax.fi` (Ring 0) und in
`kernel/user/wlibc.fi` (Ring 3) beschrieben.  Er MUSS an beiden Stellen
stehen -- der Kernel kann Ring 3 nicht nach seiner Meinung fragen --,
und genau deshalb kann er auseinanderlaufen.  Dieses Programm haelt die
Zahlen gegeneinander:

    NODE_BYTES / AX_NODE        die Groesse eines Satzes
    NAME_OFF   / AX_NAME_OFF    wo der Name anfaengt
    NAME_MAX   / AX_NAME_MAX    wie lang er sein darf
    R_*        / AR_*           die sechzehn Rollen
    S_*        / AS_*           die sieben Zustandsbits

Rueckgabe 0, wenn jede Zahl auf beiden Seiten dieselbe ist.
"""
import re
import sys


def konstanten(pfad):
    t = open(pfad, "rb").read().decode("utf-8", "replace")
    d = {}
    for name, wert in re.findall(
            r"^const ([A-Za-z_0-9]+): u64 = (0x[0-9A-Fa-f]+|\d+)",
            t, re.M):
        d[name] = int(wert, 0)
    return d


ROLLEN = ["NONE", "WINDOW", "LABEL", "BUTTON", "CHECK", "ENTRY", "PASSWORD",
          "LIST", "TABLE", "TAB", "MENUBAR", "CHOICE", "SEPARATOR",
          "SCROLLBAR", "MENU", "DIALOG"]
ZUSTAND = ["ENABLED", "FOCUSABLE", "FOCUSED", "SELECTED", "HIDDEN",
           "CHECKED", "PROTECTED"]


def main():
    k = konstanten("kernel/ax.fi")
    u = konstanten("kernel/user/wlibc.fi")
    fehler = []
    paare = [("NODE_BYTES", "AX_NODE"), ("NAME_OFF", "AX_NAME_OFF"),
             ("NAME_MAX", "AX_NAME_MAX")]
    for r in ROLLEN:
        paare.append(("R_" + r, "AR_" + r))
    for z in ZUSTAND:
        paare.append(("S_" + z, "AS_" + z))
    for a, b in paare:
        if a not in k:
            fehler.append("kernel/ax.fi kennt %s nicht" % a)
        elif b not in u:
            fehler.append("kernel/user/wlibc.fi kennt %s nicht" % b)
        elif k[a] != u[b]:
            fehler.append("%s=%d aber %s=%d" % (a, k[a], b, u[b]))
    if fehler:
        for f in fehler:
            print("    " + f)
        return 1
    print("%d Zahlen, auf beiden Seiten gleich" % len(paare))
    return 0


sys.exit(main())
