#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.normpath(os.path.join(HIER, "..", ".."))


def exakt(dst, src, a):
    num = src * a + dst * (255 - a)
    return (num * 2 + 255) // (255 * 2)


def abschneiden(dst, src, a):
    return (src * a + dst * (255 - a)) // 255


def plus127(dst, src, a):
    return (src * a + dst * (255 - a) + 127) // 255


def pan(dst, src, a):
    t = src * a + dst * (255 - a) + 128
    return (t + (t >> 8)) >> 8


FASSUNGEN = [
    ("abschneiden  (vor PAINT)", abschneiden),
    ("(num+127)/255 (Python)  ", plus127),
    ("(t+(t>>8))>>8 verworfen ", pan),
]


def messen(schritt):
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
    ("kernel/gfx/fb/fbdraw.fi", "return (src *% a +% dst *% ia +% 127) / 255"),
    ("lib/fui/comp.fi", "return (src *% a +% dst *% ia +% 127) / 255"),
    ("kernel/user/wlibc.fi",
     "return (src *% a +% dst *% ia +% 127) / 255"),
    ("tools/gfx/checkshot.py", "(old[k] * ia + new[k] * a + 127) // 255"),
    ("tools/icons/sheet.py", "+ 127"),
]


def quellen_check():
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
        moddir = p[:-3]
        if p.endswith(".fi") and os.path.isdir(moddir):
            for mod in sorted(os.listdir(moddir)):
                with open(os.path.join(moddir, mod), "rb") as mh:
                    text += mh.read().decode("utf-8", "replace")
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

    mx, summe, falsch, n = erg[FASSUNGEN[0][0]]
    if mx == 1 and falsch > n * 4 // 10:
        print("  OK    truncation: error 1 on %.2f%% of all triples"
              % (100.0 * falsch / n))
        zusagen += 1
    else:
        print("  FAIL  truncation should be off by 1 on ~48%% of the triples "
              "danebenliegen, ist: %d auf %.2f%%" % (mx, 100.0 * falsch / n))
        fehler += 1

    for name in ("(num+127)/255 (Python)  ", "(t+(t>>8))>>8 verworfen "):
        mx, summe, falsch, n = erg[name]
        if mx == 0 and falsch == 0:
            print("  OK    %s is exact on all %d triples" % (name, n))
            zusagen += 1
        else:
            print("  FAIL  %s: max=%d, %d falsch" % (name, mx, falsch))
            fehler += 1

    ungleich = 0
    for a in range(0, 256, schritt):
        for src in range(256):
            for dst in range(256):
                if pan(dst, src, a) != plus127(dst, src, a):
                    ungleich += 1
    if ungleich == 0:
        print("  OK    kernel and host deliver on all %d triples "
              "DENSELBEN Wert" % gesamt)
        zusagen += 1
    else:
        print("  FAIL  kernel and host differ on %d triples"
              % ungleich)
        fehler += 1

    schlecht = randbedingungen()
    if not schlecht:
        print("  OK    a=0 leaves the background and a=255 gives the new "
              "Farbe -- bei allen drei Fassungen")
        zusagen += 1
    else:
        for z in schlecht:
            print("  FAIL  %s" % z)
        fehler += 1

    if "--quellen" in sys.argv:
        fehlt = quellen_check()
        if not fehlt:
            print("  OK    all %d occurrences carry the same rounding"
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
