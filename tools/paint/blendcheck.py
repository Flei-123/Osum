#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/paint/blendcheck.py -- DIE MISCHUNG, GEGEN DIE EXAKTE RECHNUNG.
#
# Runde PAINT hat in diesem Baum VIER Fassungen derselben Zeile
# gefunden -- src-over, ganzzahlig, acht Bit je Kanal:
#
#     kernel/fb.fi           (neu in dieser Runde)
#     kernel/wm.fi           `blend`
#     kernel/user/wlibc.fi   `blend`
#     tools/gfx/checkshot.py `mische`   -- der Pruefer auf dem Wirt
#
# und eine fuenfte, die schon immer anders rundete:
#
#     tools/icons/sheet.py   `mische`   -- mit `+ 127`
#
# Das ist genau die Sorte Doppelung, die niemand bemerkt, solange die
# Abweichung eins ist: ein Bildschirmfoto wird mit Toleranz geprueft,
# und eine Toleranz verdeckt einen systematischen Fehler.
#
# DIESES SKRIPT MISST DEN FEHLER, statt ihn zu vermuten. Es rechnet ALLE
# 256 * 256 * 256 = 16 777 216 Tripel (a, src, dst) durch, fuer jede
# Fassung, und haelt sie gegen die exakte, kaufmaennisch gerundete
# Rechnung.
#
#   ./tools/paint/blendcheck.py            -- die Messung, alle Tripel
#   ./tools/paint/blendcheck.py --schnell  -- jedes 7. a, fuer den Laeufer
#   ./tools/paint/blendcheck.py --quellen  -- prueft zusaetzlich, dass in
#                                             den fuenf Dateien wirklich
#                                             die neue Zeile steht
#
# Beendigungscode 0 = alle Zusagen gehalten.
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.normpath(os.path.join(HIER, "..", ".."))


def exakt(dst, src, a):
    """(src*a + dst*(255-a)) / 255, kaufmaennisch gerundet."""
    num = src * a + dst * (255 - a)
    return (num * 2 + 255) // (255 * 2)


def abschneiden(dst, src, a):
    """Was bis Runde PAINT in drei der vier Dateien stand."""
    return (src * a + dst * (255 - a)) // 255


def plus127(dst, src, a):
    """Die Fassung der Python-Seite seit Runde PAINT."""
    return (src * a + dst * (255 - a) + 127) // 255


def schieben(dst, src, a):
    """Die exakte Fassung OHNE Division -- gemessen, verworfen.

    t = num + 128, dann (t + (t >> 8)) >> 8.  Ebenso exakt wie
    `plus127`, aber auf dem Messrechner ein Fuenftel langsamer (526
    gegen 646 Takte je Bildpunkt im Kern, 6.17 gegen 6.65 nativ).  Sie
    steht hier weiter, damit die Zusage "beide exakten Fassungen
    liefern denselben Wert" pruefbar bleibt -- und damit niemand die
    Entscheidung ein zweites Mal ohne Messung trifft.
    """
    t = src * a + dst * (255 - a) + 128
    return (t + (t >> 8)) >> 8


FASSUNGEN = [
    ("abschneiden  (vor PAINT)", abschneiden),
    ("(num+127)/255 (Python)  ", plus127),
    ("(t+(t>>8))>>8 verworfen ", schieben),
]


def messen(schritt):
    """Gibt {name: [maxfehler, summe, falsch, gesamt]}."""
    erg = dict((name, [0, 0, 0, 0]) for name, _ in FASSUNGEN)
    for a in range(0, 256, schritt):
        ia = 255 - a
        for src in range(256):
            sa = src * a
            for dst in range(256):
                num = sa + dst * ia
                soll = (num * 2 + 255) // 510
                for name, f in FASSUNGEN:
                    d = abs(f(dst, src, a) - soll)
                    e = erg[name]
                    if d > e[0]:
                        e[0] = d
                    e[1] += d
                    if d:
                        e[2] += 1
                    e[3] += 1
    return erg


def randbedingungen():
    """a = 0 und a = 255 muessen bei ALLEN Fassungen exakt sein.

    Eine Mischung, die bei voller Deckung nicht die neue Farbe liefert,
    faerbt jede undurchsichtige Flaeche um -- der Fehler, der aussieht
    wie ein kaputter Bildschirm und nicht wie eine Rundung.
    """
    schlecht = []
    for name, f in FASSUNGEN:
        for v in range(256):
            if f(v, 0, 0) != v:
                schlecht.append("%s: a=0 aendert dst=%d" % (name, v))
                break
            if f(0, v, 255) != v:
                schlecht.append("%s: a=255 liefert src=%d nicht" % (name, v))
                break
    return schlecht


QUELLEN = [
    ("kernel/fb.fi", "return (src *% a +% dst *% ia +% 127) / 255"),
    ("kernel/wm.fi", "return (src *% a +% dst *% ia +% 127) / 255"),
    ("kernel/user/wlibc.fi",
     "return (src *% a +% dst *% ia +% 127) / 255"),
    ("tools/gfx/checkshot.py", "(alt[k] * ia + neu[k] * a + 127) // 255"),
    ("tools/icons/sheet.py", "+ 127"),
]


def quellen_pruefen():
    fehlt = []
    for datei, nadel in QUELLEN:
        p = os.path.join(WURZEL, datei)
        try:
            fh = open(p, "rb")
        except OSError:
            fehlt.append("%s fehlt" % datei)
            continue
        text = fh.read().decode("utf-8", "replace")
        fh.close()
        if nadel not in text:
            fehlt.append("%s: %r steht nicht darin" % (datei, nadel))
    return fehlt


def main():
    schnell = "--schnell" in sys.argv
    schritt = 7 if schnell else 1
    fehler = 0
    zusagen = 0

    erg = messen(schritt)
    gesamt = erg[FASSUNGEN[0][0]][3]
    print("PAINT-BLEND: %d Tripel (a, src, dst)%s"
          % (gesamt, "  [--schnell: jedes 7. a]" if schnell else ""))
    for name, _ in FASSUNGEN:
        mx, summe, falsch, n = erg[name]
        print("   %s  max=%d  mittel=%.6f  falsch=%d (%.3f%%)"
              % (name, mx, summe / float(n), falsch, 100.0 * falsch / n))

    # ZUSAGE 1: die alte Fassung liegt WIRKLICH daneben, und zwar nicht
    # an einem Sonderfall, sondern auf fast der Haelfte aller Tripel.
    mx, summe, falsch, n = erg[FASSUNGEN[0][0]]
    if mx == 1 and falsch > n * 4 // 10:
        print("  OK    abschneiden: Fehler 1 auf %.2f%% aller Tripel"
              % (100.0 * falsch / n))
        zusagen += 1
    else:
        print("  FAIL  abschneiden sollte auf ~48%% der Tripel um 1 "
              "danebenliegen, ist: %d auf %.2f%%" % (mx, 100.0 * falsch / n))
        fehler += 1

    # ZUSAGE 2 und 3: beide neuen Fassungen sind EXAKT, nicht "besser".
    for name in ("(num+127)/255 (Python)  ", "(t+(t>>8))>>8 verworfen "):
        mx, summe, falsch, n = erg[name]
        if mx == 0 and falsch == 0:
            print("  OK    %s ist auf allen %d Tripeln exakt" % (name, n))
            zusagen += 1
        else:
            print("  FAIL  %s: max=%d, %d falsch" % (name, mx, falsch))
            fehler += 1

    # ZUSAGE 4: Kern und Wirt rechnen BILDPUNKTGLEICH. Das ist die
    # eigentliche Zusage dieser Datei -- ohne sie kann kein
    # Bildschirmfoto den Kern widerlegen.
    # Kern UND Wirt rechnen seit PAINT beide `(num + 127) / 255`; die
    # Zusage ist trotzdem nicht leer, denn sie haelt zusaetzlich die
    # verworfene, schiebende Fassung dagegen -- waere die je wieder
    # eingebaut, muesste sie bildpunktgleich sein.
    ungleich = 0
    for a in range(0, 256, schritt):
        for src in range(256):
            for dst in range(256):
                if schieben(dst, src, a) != plus127(dst, src, a):
                    ungleich += 1
    if ungleich == 0:
        print("  OK    Kern und Wirt liefern auf allen %d Tripeln "
              "DENSELBEN Wert" % gesamt)
        zusagen += 1
    else:
        print("  FAIL  Kern und Wirt unterscheiden sich auf %d Tripeln"
              % ungleich)
        fehler += 1

    # ZUSAGE 5: die Raender.
    schlecht = randbedingungen()
    if not schlecht:
        print("  OK    a=0 laesst den Grund und a=255 gibt die neue "
              "Farbe -- bei allen drei Fassungen")
        zusagen += 1
    else:
        for z in schlecht:
            print("  FAIL  %s" % z)
        fehler += 1

    # ZUSAGE 6: und die Zeile steht wirklich in allen fuenf Dateien.
    if "--quellen" in sys.argv:
        fehlt = quellen_pruefen()
        if not fehlt:
            print("  OK    alle %d Fundstellen tragen dieselbe Rundung"
                  % len(QUELLEN))
            zusagen += 1
        else:
            for z in fehlt:
                print("  FAIL  %s" % z)
            fehler += 1

    print("PAINT-BLEND: %d Zusagen, %d Fehler" % (zusagen, fehler))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
