#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/laden/tippen.py -- aus einem Satz Tastendruecke fuer den Monitor.

    tippen.py "ota suchen" [--warte 3] [--ohne-eingabe] > befehle.txt

Die Ausgabe ist eine Befehlsdatei fuer `tools/wm/monitor.py`: eine Zeile
`sendkey <taste>` je Zeichen, am Ende `sendkey ret`.

WARUM UEBER DIE TASTATUR UND NICHT UEBER `script=`. `script=` ist die
SERIELLE Konsole -- was dort steht, laeuft, aber es steht nie auf dem
Bildschirm. Ein Laden, der beweisen soll, dass man ihn BEDIENEN kann,
muss durch dieselbe Tuer wie ein Mensch: PS/2-Tastatur, Fensterserver,
Terminalfenster. Genau diese Strecke misst Runde K10 mit
`tools/wm/monitor.py`, und hier wird sie benutzt statt nachgebaut.

Die Tastennamen sind die von QEMU (`sendkey`): Buchstaben und Ziffern
heissen wie sie selbst, das Leerzeichen `spc`, der Bindestrich `minus`,
der Schraegstrich `slash`, der Punkt `dot`. Mehr braucht ein Befehl
dieser Runde nicht -- und was hier fehlt, faellt sofort auf, weil das
Programm dann abbricht statt still ein anderes Zeichen zu tippen.
"""
import sys

TASTEN = {
    " ": "spc", "-": "minus", "/": "slash", ".": "dot", ",": "comma",
    "=": "equal", ";": "semicolon", "\\": "backslash",
    # `>` ist die UMSCHALTETE Punkt-Taste. QEMU kennt dafuer die
    # Schreibweise `shift-<taste>`; ohne die Umschaltung kaeme ein
    # Punkt an, und der Befehl liefe -- nur eben anders, als er
    # dasteht. Genau die Art Fehler, die ein Bildschirmfoto nicht
    # zeigt.
    ">": "shift-dot", "<": "shift-comma", ":": "shift-semicolon",
}


def taste(c):
    if c in TASTEN:
        return TASTEN[c]
    if ("a" <= c <= "z") or ("0" <= c <= "9"):
        return c
    raise SystemExit("tippen: fuer '%s' ist keine Taste eingetragen" % c)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    warte = 3
    eingabe = True
    text = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--warte":
            i += 1
            warte = float(argv[i])
        elif a == "--ohne-eingabe":
            eingabe = False
        else:
            text.append(a)
        i += 1
    zeilen = []
    for satz in text:
        for c in satz:
            zeilen.append("sendkey " + taste(c))
        if eingabe:
            zeilen.append("sendkey ret")
        zeilen.append("warte %g" % warte)
    print("\n".join(zeilen))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
