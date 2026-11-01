#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/loader/tippen.py -- aus einem Satz Tastendruecke fuer den Monitor.

    tippen.py "ota search" [--warte 3] [--ohne-eingabe] > befehle.txt

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

KEYS = {
    " ": "spc", "-": "minus", "/": "slash", ".": "dot", ",": "comma",
    "=": "equal", ";": "semicolon", "\\": "backslash",
    ">": "shift-dot", "<": "shift-comma", ":": "shift-semicolon",
}


def key(c):
    if c in KEYS:
        return KEYS[c]
    if ("a" <= c <= "z") or ("0" <= c <= "9"):
        return c
    raise SystemExit("tippen: fuer '%s' ist keine Taste eingetragen" % c)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    warte = 3
    input_ = True
    text = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--warte":
            i += 1
            warte = float(argv[i])
        elif a == "--ohne-eingabe":
            input_ = False
        else:
            text.append(a)
        i += 1
    lines = []
    for satz in text:
        for c in satz:
            lines.append("sendkey " + key(c))
        if input_:
            lines.append("sendkey ret")
        lines.append("warte %g" % warte)
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
