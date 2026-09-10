#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/alltag/patch.py -- EIN TEXTSTUECK GEGEN EIN ANDERES TAUSCHEN, GENAU EINMAL.

    patch.py <datei> <alt-datei> <neu-datei>

Die Runde ALLTAG aendert Kernel-Dateien mit 5000 bis 9000 Zeilen. Ein
Werkzeug, das "irgendwo" ersetzt, ersetzt irgendwann das Falsche; dieses
hier verlangt, dass das alte Stueck GENAU EINMAL vorkommt, und sagt
sonst laut nein. Es ist nur ein Bauhelfer und wird von keiner Abnahme
gebraucht.
"""
import sys


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    pfad, alt_p, neu_p = sys.argv[1:4]
    text = open(pfad, "rb").read().decode("utf-8", "surrogateescape")
    alt = open(alt_p, "rb").read().decode("utf-8", "surrogateescape")
    neu = open(neu_p, "rb").read().decode("utf-8", "surrogateescape")
    n = text.count(alt)
    if n != 1:
        print("patch.py: %s: das alte Stueck kommt %d-mal vor, nicht einmal" % (pfad, n))
        return 1
    text = text.replace(alt, neu, 1)
    open(pfad, "wb").write(text.encode("utf-8", "surrogateescape"))
    print("patch.py: %s: ersetzt (%d -> %d Zeichen)" % (pfad, len(alt), len(neu)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
