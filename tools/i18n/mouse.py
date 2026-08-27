#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/i18n/mouse.py -- eine Befehlsdatei fuer tools/wm/monitor.py.
#
#   python3 tools/i18n/mouse.py <x1> <y1> [<x2> <y2> ...] [--park <x> <y>]
#
# Schreibt auf stdout, was der QEMU-Monitor braucht, um NACHEINANDER an
# die genannten Stellen zu fahren und dort zu klicken.
#
# WARUM DAS NICHT EIN EINZIGER BEFEHL IST. Der Monitor kennt nur
# `mouse_move <dx> <dy>` -- eine RELATIVE Bewegung, denn ein PS/2-Geraet
# schickt Unterschiede und keine Orte. Ein Paket traegt neun Bit je
# Achse; groessere Spruenge zerlegt QEMU in mehrere Pakete, und geht
# eines verloren, ist der Endpunkt ein anderer. Deshalb -- genau wie in
# tools/wm/monitor.py beschrieben und in Runde K10 gemessen:
#
#   1. Mehrmals kraeftig nach LINKS OBEN. Dort haelt der Anschlag, und
#      die Vorgeschichte ist geloescht. Ab hier ist (0, 0) bekannt.
#   2. In Schritten unter 128 an die gemeinte Stelle.
#   3. Taste runter, kurz warten, Taste hoch.
#
# `--park` faehrt zum Schluss an eine Stelle, OHNE dort zu klicken.
# Warum das gebraucht wird: ein Knopf, auf dem der Zeiger stehenbleibt,
# ist HERVORGEHOBEN -- `wlib` malt ihn dann in T_BTNHI statt in T_BTN.
# Ein Bildschirmfoto misst dann eine andere Hintergrundfarbe als die,
# die das Programm gemeldet hat, und `schau.py ttext` rechnet jede
# Zwischenstufe der Kantenglaettung gegen den falschen Grund. Und der
# Pfeil selbst liegt UEBER dem Text: gemessen 19 falsche von 526
# Tintenpunkten, alle unter der Pfeilspitze.
#
# ZWISCHEN ZWEI KLICKS WIRD GEWARTET, und zwar reichlich. Der
# Fensterserver, die Anwendung und der Zeiger laufen auf EINEM
# Prozessor; ein Klick, der kommt, bevor der vorige verarbeitet ist,
# geht an ein Bedienelement, das noch gar nicht da ist. Gemessen: unter
# einer halben Sekunde je Klick blieb der Reiter zu.
import sys


def fahre(aus, dx, dy):
    """In Schritten unter 128 -- ein Paket, ein Schritt."""
    while dx or dy:
        sx = max(-120, min(120, dx))
        sy = max(-120, min(120, dy))
        aus.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy


def klick(aus, x, y, von=(0, 0)):
    fahre(aus, x - von[0], y - von[1])
    aus.append("warte 0.3")
    aus.append("mouse_button 1")
    aus.append("warte 0.2")
    aus.append("mouse_button 0")
    aus.append("warte 0.8")
    return (x, y)


def main():
    roh = sys.argv[1:]
    park = None
    if "--park" in roh:
        i = roh.index("--park")
        park = (int(roh[i + 1]), int(roh[i + 2]))
        roh = roh[:i] + roh[i + 3:]
    a = [int(v) for v in roh]
    if len(a) < 2 or len(a) % 2 != 0:
        print(__doc__)
        return 2
    aus = []
    aus.append("# in die linke obere Ecke -- der Anschlag loescht die"
               " Vorgeschichte")
    for _ in range(12):
        aus.append("mouse_move -120 -120")
    aus.append("warte 0.5")
    hier = (0, 0)
    for i in range(0, len(a), 2):
        hier = klick(aus, a[i], a[i + 1], hier)
    # ZUM SCHLUSS DEN ZEIGER WEGFAHREN. Der Fensterserver malt ihn UEBER
    # allem; bleibt er nach dem letzten Klick auf dem Knopf stehen,
    # verdeckt der Pfeil ein paar Bildpunkte des Knopftextes -- gemessen
    # 19 von 526, alle im 'e' unter der Pfeilspitze. Ein Foto misst
    # sonst den Zeiger.
    if park is not None:
        aus.append("# den Zeiger vom Knopf wegfahren -- OHNE zu klicken")
        fahre(aus, park[0] - hier[0], park[1] - hier[1])
        aus.append("warte 1.0")
    aus.append("warte 2.0")
    print("\n".join(aus))
    return 0


sys.exit(main())
