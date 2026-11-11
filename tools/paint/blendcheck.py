#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HIER, "..", ".."))


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
    bad_2 = []
    for name, f in FASSUNGEN:
        for v in range(256):
            if f(v, 0, 0) != v:
                bad_2.append("%s: a=0 aendert dst=%d" % (name, v))
                break
            if f(0, v, 255) != v:
                bad_2.append("%s: a=255 liefert src=%d nicht" % (name, v))
                break
    return bad_2


QUELLEN = [
    ("kernel/gfx/fb/fbdraw.fi", "return (src *% a +% dst *% ia +% 127) / 255"),
    ("lib/fui/comp.fi", "return (src *% a +% dst *% ia +% 127) / 255"),
    ("kernel/user/uikit/uidraw.fi",
     "return (src *% a +% dst *% ia +% 127) / 255"),
    ("tools/gfx/checkshot.py", "(old[k] * ia + new[k] * a + 127) // 255"),
    ("tools/icons/sheet.py", "+ 127"),
]


def quellen_check():
    missing = []
    for file_2, nadel in QUELLEN:
        p = os.path.join(ROOT, file_2)
        try:
            fh = open(p, "rb")
        except OSError:
            missing.append("%s fehlt" % file_2)
            continue
        text = fh.read().decode("utf-8", "replace")
        fh.close()
        moddir = p[:-3]
        if p.endswith(".fi") and os.path.isdir(moddir):
            for mod in sorted(os.listdir(moddir)):
                with open(os.path.join(moddir, mod), "rb") as mh:
                    text += mh.read().decode("utf-8", "replace")
        if nadel not in text:
            missing.append("%s: %r steht nicht darin" % (file_2, nadel))
    return missing


def main():
    fast = "--fast" in sys.argv
    schritt = 7 if fast else 1
    error = 0
    zusagen = 0

    erg = messen(schritt)
    gesamt = erg[FASSUNGEN[0][0]][3]
    print("PAINT-BLEND: %d Tripel (a, src, dst)%s"
          % (gesamt, "  [--fast: jedes 7. a]" if fast else ""))
    for name, _ in FASSUNGEN:
        mx, sum_2, wrong, n = erg[name]
        print("   %s  max=%d  mittel=%.6f  falsch=%d (%.3f%%)"
              % (name, mx, sum_2 / float(n), wrong, 100.0 * wrong / n))

    mx, sum_2, wrong, n = erg[FASSUNGEN[0][0]]
    if mx == 1 and wrong > n * 4 // 10:
        print("  OK    truncation: error 1 on %.2f%% of all triples"
              % (100.0 * wrong / n))
        zusagen += 1
    else:
        print("  FAIL  truncation should be off by 1 on ~48%% of the triples "
              "danebenliegen, ist: %d auf %.2f%%" % (mx, 100.0 * wrong / n))
        error += 1

    for name in ("(num+127)/255 (Python)  ", "(t+(t>>8))>>8 verworfen "):
        mx, sum_2, wrong, n = erg[name]
        if mx == 0 and wrong == 0:
            print("  OK    %s is exact on all %d triples" % (name, n))
            zusagen += 1
        else:
            print("  FAIL  %s: max=%d, %d falsch" % (name, mx, wrong))
            error += 1

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
        error += 1

    bad_2 = randbedingungen()
    if not bad_2:
        print("  OK    a=0 leaves the background and a=255 gives the new "
              "Farbe -- bei allen drei Fassungen")
        zusagen += 1
    else:
        for z in bad_2:
            print("  FAIL  %s" % z)
        error += 1

    if "--quellen" in sys.argv:
        missing = quellen_check()
        if not missing:
            print("  OK    all %d occurrences carry the same rounding"
                  % len(QUELLEN))
            zusagen += 1
        else:
            for z in missing:
                print("  FAIL  %s" % z)
            error += 1

    print("PAINT-BLEND: %d Zusagen, %d Fehler" % (zusagen, error))
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
