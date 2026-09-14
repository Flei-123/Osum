#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/lib/tasten.py -- Tasten schicken und auf ihre WIRKUNG warten.

    tasten.py <monitor.sock> <serielle-datei> taste [taste ...]
              [--bereit TEXT] [--zeit SEKUNDEN] [--vorlauf SEKUNDEN]

WARUM ES DIESE DATEI GIBT.

Vier Abschnitte der Abnahme -- `osum`, `userland`, `k17` und
`systembus` -- schickten ihre Tastendruecke bisher so:

    for key in ["l", "s", "ret"]:
        s.sendall(("sendkey %s\\n" % key).encode())
        time.sleep(0.3)

und pruefen danach

    keys that arrived over IRQ1: 2, expected eq 3

Auf einer freien Maschine reichen 0,3 s. Auf dieser Maschine, auf der
sich bis zu sechs fremde QEMU-Prozesse denselben Wirt teilen, reichen
sie nicht: QEMU bekommt seine Zeitscheibe nicht, der Tastendruck liegt
noch in der virtuellen Tastatur, und der naechste kommt schon
hinterher. Gezaehlt werden dann zwei statt drei.

DAS IST KEIN FEHLER IN OSUM, UND DER TEST HAT IHN AUCH NIE GEMESSEN.
Er hat gemessen, ob der Wirt gerade schnell genug war. Ein Test, der
unter Last luegt, ist kein Test -- er sagt an einem ruhigen Abend
"gruen" und an einem vollen "rot", und beide Male steht dasselbe im
Kern.

WIE ES STATT DESSEN GEMACHT WIRD.

Der Kern meldet GENAU EINE Zeile `key: ` je Taste, die ueber IRQ1
angekommen ist (`kernel/kbd.fi`, Zusage von Runde 62; die Zeile 602
sagt es woertlich). Das ist ein EREIGNIS, und darauf laesst sich
warten, statt auf die Uhr zu sehen:

    Taste schicken  ->  warten, bis die Zahl der `key: `-Zeilen
                        um eins gestiegen ist  ->  naechste Taste

Damit haengt die Geschwindigkeit an der Maschine und nicht mehr die
Richtigkeit. Auf einem freien Wirt laeuft es schneller als vorher
(kein festes Warten mehr), auf einem vollen dauert es laenger -- und
zaehlt in beiden Faellen dasselbe.

WAS DABEI NICHT ENTSCHAERFT WIRD. Die Zusage bleibt Wort fuer Wort
dieselbe: es muessen so viele Tasten ueber IRQ1 ankommen, wie
geschickt wurden. Kommt eine nicht an, wartet dieses Programm bis zum
Zeitlimit und meldet sie als fehlend -- der Abschnitt wird rot, wie er
es soll. Neu ist nur, dass "nicht angekommen" jetzt heisst "der Kern
hat sie nicht verarbeitet" und nicht mehr "der Wirt war beschaeftigt".

Die Tastennamen sind die von QEMU (`sendkey`).

Rueckgabe: 0, wenn jede Taste ihre Zeile bekommen hat; 1 sonst. Auf
stdout steht eine Zeile je Taste, damit im Protokoll steht, wie lange
es gedauert hat.
"""
import os
import re
import socket
import sys
import time

# Wie lange auf EINE Taste gewartet wird, bevor sie als verloren gilt.
# Grosszuegig, weil der Wirt geteilt wird -- das Zeitlimit ist die
# Notbremse und nicht die Messung.
ZEIT_JE_TASTE = 12.0
# Wie lange gewartet wird, bis der Kern ueberhaupt bereit ist.
ZEIT_BEREIT = 40.0


def zeilen(pfad):
    """Wie viele `key: `-Zeilen stehen schon in der seriellen Ausgabe."""
    try:
        with open(pfad, "rb") as f:
            return f.read().count(b"key: ")
    except OSError:
        return 0


def warte_auf(pfad, text, grenze):
    """Warten, bis TEXT in der seriellen Ausgabe steht."""
    roh = text.encode()
    ende = time.time() + grenze
    while time.time() < ende:
        try:
            with open(pfad, "rb") as f:
                if roh in f.read():
                    return True
        except OSError:
            pass
        time.sleep(0.05)
    return False


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    sock = argv[1]
    seriell = argv[2]
    tasten = []
    bereit = None
    zeit = ZEIT_JE_TASTE
    vorlauf = 0.4
    i = 3
    while i < len(argv):
        a = argv[i]
        if a == "--bereit":
            i += 1
            bereit = argv[i]
        elif a == "--zeit":
            i += 1
            zeit = float(argv[i])
        elif a == "--vorlauf":
            i += 1
            vorlauf = float(argv[i])
        else:
            tasten.append(a)
        i += 1

    if bereit and not warte_auf(seriell, bereit, ZEIT_BEREIT):
        print("tasten: der Kern hat '%s' nicht gemeldet" % bereit)
        return 1

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(sock)
    # Ein kurzer Vorlauf bleibt: der Monitor selbst muss seine
    # Begruessung losgeworden sein, bevor er Befehle annimmt. Das ist
    # eine Eigenschaft von QEMU und nicht von Osum.
    time.sleep(vorlauf)

    fehlend = []
    for nr, taste in enumerate(tasten, 1):
        vorher = zeilen(seriell)
        s.sendall(("sendkey %s\n" % taste).encode())
        anfang = time.time()
        ende = anfang + zeit
        angekommen = False
        while time.time() < ende:
            if zeilen(seriell) > vorher:
                angekommen = True
                break
            time.sleep(0.02)
        dauer = time.time() - anfang
        if angekommen:
            print("tasten: %2d/%d  %-10s angekommen nach %.2fs"
                  % (nr, len(tasten), taste, dauer))
        else:
            print("tasten: %2d/%d  %-10s NICHT angekommen (%.1fs gewartet)"
                  % (nr, len(tasten), taste, dauer))
            fehlend.append(taste)
    s.close()

    if fehlend:
        print("tasten: %d von %d Tasten kamen nicht an: %s"
              % (len(fehlend), len(tasten), " ".join(fehlend)))
        return 1
    print("tasten: alle %d Tasten sind ueber IRQ1 angekommen" % len(tasten))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
