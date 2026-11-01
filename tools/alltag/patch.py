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
    path_2, alt_p, new_p = sys.argv[1:4]
    text = open(path_2, "rb").read().decode("utf-8", "surrogateescape")
    alt = open(alt_p, "rb").read().decode("utf-8", "surrogateescape")
    new = open(new_p, "rb").read().decode("utf-8", "surrogateescape")
    n = text.count(alt)
    if n != 1:
        print("patch.py: %s: the old piece occurs %d times, not once" % (path_2, n))
        return 1
    text = text.replace(alt, new, 1)
    open(path_2, "wb").write(text.encode("utf-8", "surrogateescape"))
    print("patch.py: %s: ersetzt (%d -> %d Zeichen)" % (path_2, len(alt), len(new)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
