#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/sync/boese.py -- DER BOESARTIGE SERVER.

Der Anbieter ist nicht nur neugierig, er ist feindlich. Er darf alles,
was jemand darf, dem die Oktette gehoeren: sie aendern, alte
zurueckspielen, fremde unterschieben, zu grosse liefern. Dieses Programm
tut genau das mit einem herausgeholten Speicher, und der Testlauf spielt
das Ergebnis wieder ein.

    boese.py aendern      <speicher>            ein Bit in PACK kippen
    boese.py rueckschritt <speicher> <alt>      die alte Wurzel wieder hin
    boese.py fremd        <speicher>            zwei Bloecke vertauschen
    boese.py gross        <speicher>            ein Block wird laenger
    boese.py wurzelluege  <speicher>            die Wurzel zeigt woandershin
    boese.py halbe        <speicher>            ROOT nur halb geschrieben

Jeder Fall hat eine ERWARTUNG, und die steht im Laeufer: `sync abgleich`
muss ihn erkennen und ablehnen, nicht "irgendwie weitermachen".
"""
import os
import shutil
import sys


def lade(sp, name):
    p = os.path.join(sp, name)
    return open(p, "rb").read() if os.path.exists(p) else b""


def sichere(sp, name, d):
    open(os.path.join(sp, name), "wb").write(d)


def aendern(sp):
    d = bytearray(lade(sp, "PACK"))
    if not d:
        return "PACK ist leer"
    # Ein Oktett in der Mitte des ersten Blocks -- also im Geheimtext,
    # nicht im Siegel. Genau das muss Poly1305 fangen.
    d[100] ^= 0x01
    sichere(sp, "PACK", bytes(d))
    return "ein Bit in PACK bei Oktett 100 gekippt"


def rueckschritt(sp, alt):
    shutil.copy(alt, os.path.join(sp, "ROOT"))
    return "die alte, ECHT versiegelte Wurzel wieder eingespielt"


def fremd(sp):
    idx = lade(sp, "INDEX").split(b"\n")
    eintraege = [z.split(b"\t") for z in idx if z.count(b"\t") == 2]
    if len(eintraege) < 2:
        return "zu wenige Bloecke"
    d = bytearray(lade(sp, "PACK"))
    a = (int(eintraege[0][1]), int(eintraege[0][2]))
    b = (int(eintraege[1][1]), int(eintraege[1][2]))
    # Block B unter dem Namen von Block A ausliefern. Beide sind ECHT
    # versiegelt -- nur am falschen Platz. Das faengt nur das AAD.
    d[a[0]:a[0] + a[1]] = d[b[0]:b[0] + b[1]]
    sichere(sp, "PACK", bytes(d))
    return "Block 2 unter dem Namen von Block 1 ausgeliefert"


def gross(sp):
    idx = lade(sp, "INDEX").split(b"\n")
    aus = []
    getan = False
    for z in idx:
        if z.count(b"\t") == 2 and not getan:
            t = z.split(b"\t")
            t[2] = b"999999"
            z = b"\t".join(t)
            getan = True
        aus.append(z)
    sichere(sp, "INDEX", b"\n".join(aus))
    return "ein Block behauptet, 999999 Oktette lang zu sein"


def wurzelluege(sp):
    d = lade(sp, "ROOT").split(b" ")
    if len(d) < 4:
        return "keine Wurzel"
    # Der Name wird veraendert, das Siegel bleibt. Muss auffallen.
    n = bytearray(d[2])
    n[0] = ord("0") if n[0] != ord("0") else ord("1")
    d[2] = bytes(n)
    sichere(sp, "ROOT", b" ".join(d))
    return "die Wurzel zeigt auf einen anderen Block, das Siegel ist alt"


def halbe(sp):
    d = lade(sp, "ROOT")
    sichere(sp, "ROOT", d[:len(d) // 2])
    return "ROOT nur zur Haelfte geschrieben (Stromausfall)"


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    was, sp = sys.argv[1], sys.argv[2]
    if was == "aendern":
        print(aendern(sp))
    elif was == "rueckschritt":
        print(rueckschritt(sp, sys.argv[3]))
    elif was == "fremd":
        print(fremd(sp))
    elif was == "gross":
        print(gross(sp))
    elif was == "wurzelluege":
        print(wurzelluege(sp))
    elif was == "halbe":
        print(halbe(sp))
    else:
        print(__doc__)
        sys.exit(2)
