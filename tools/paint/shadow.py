#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys


def ppm_read(pfad):
    with open(pfad, "rb") as fh:
        d = fh.read()
    if not d.startswith(b"P6"):
        raise SystemExit("%s ist kein P6-PPM" % pfad)
    felder = []
    i = 2
    while len(felder) < 3:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while i < len(d) and d[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        felder.append(int(d[i:j]))
        i = j
    i += 1
    w, h, _mx = felder
    return w, h, d[i:i + w * h * 3]


def punkt(bild, w, h, x, y):
    if x < 0 or y < 0 or x >= w or y >= h:
        return None
    o = (y * w + x) * 3
    return (bild[o], bild[o + 1], bild[o + 2])


def bright(p):
    """Wahrgenommene Helligkeit -- Rec. 601, ganzzahlig."""
    return (p[0] * 299 + p[1] * 587 + p[2] * 114) // 1000


def schatten(argv):
    """Der Schatten, gegen den Lauf ohne ihn."""
    without, mit = argv[0], argv[1]
    x, y, w0, h0 = (int(v) for v in argv[2:6])
    reach = 6
    if "--reach" in argv:
        reach = int(argv[argv.index("--reach") + 1])
    wa, ha, A = ppm_read(without)
    wb, hb, B = ppm_read(mit)
    if (wa, ha) != (wb, hb):
        print("  FAIL  verschiedene Bildgroessen")
        return 1
    zy = y + h0 // 2
    rand = x + w0
    print("PAINT-SCHATTEN: Fenster %d,%d %dx%d  Zeile y=%d  "
          "rechte Aussenkante x=%d" % (x, y, w0, h0, zy, rand - 1))
    ov = []
    mv = []
    for k in range(reach + 3):
        pa = punkt(A, wa, ha, rand + k, zy)
        pb = punkt(B, wb, hb, rand + k, zy)
        ov.append(None if pa is None else bright(pa))
        mv.append(None if pb is None else bright(pb))
    print("   without shadow: %s"
          % " ".join("--" if v is None else "%3d" % v for v in ov))
    print("   mit  Schatten: %s"
          % " ".join("--" if v is None else "%3d" % v for v in mv))
    diff = [0 if (a is None or b is None) else a - b
            for a, b in zip(ov, mv)]
    print("   Unterschied:   %s" % " ".join("%3d" % d for d in diff))

    zusagen = 0
    error = 0
    dunkler = sum(1 for d in diff if d > 0)
    if dunkler >= 3 and min(diff) >= 0:
        print("  OK    %d pixels are darker than without shadow, "
              "und keiner ist heller" % dunkler)
        zusagen += 1
    else:
        print("  FAIL  %d dunkler, kleinster Unterschied %d"
              % (dunkler, min(diff)))
        error += 1
    innen = diff[:dunkler] if dunkler else []
    monoton = all(innen[i] >= innen[i + 1] for i in range(len(innen) - 1))
    if monoton and innen:
        print("  OK    the difference falls off monotonically towards the outside "
              "(%d bis %d Helligkeitsstufen)" % (innen[0], innen[-1]))
        zusagen += 1
    else:
        print("  FAIL  the difference is not monotonic: %s" % innen)
        error += 1
    if dunkler <= reach + 1 and (len(diff) > dunkler and diff[-1] == 0):
        print("  OK    it ends after %d pixels (reach=%d) -- "
              "dahinter ist das Bild unveraendert" % (dunkler, reach))
        zusagen += 1
    else:
        print("  FAIL  er reicht %d Bildpunkte weit, erwartet hoechstens "
              "%d" % (dunkler, reach + 1))
        error += 1
    print("PAINT-SCHATTEN: %d Zusagen, %d Fehler" % (zusagen, error))
    return 1 if error else 0


def ecke(argv):
    """Die Ecke, gegen den Lauf mit der eckigen."""
    without, mit = argv[0], argv[1]
    x, y = int(argv[2]), int(argv[3])
    r = 8
    if "--r" in argv:
        r = int(argv[argv.index("--r") + 1])
    wa, ha, A = ppm_read(without)
    wb, hb, B = ppm_read(mit)

    def gemischt(b, w, h):
        """Bildpunkte im Eckquadrat, die WEDER Rahmen NOCH Grund sind.

        Die Rahmenfarbe wird tief im Fenster abgelesen (r, r hinter der
        Ecke), die Grundfarbe weit ausserhalb (drei Bildpunkte davor) --
        beide aus DEMSELBEN Bild, damit kein Schema-Unterschied
        hineinrechnet.
        """
        frame = punkt(b, w, h, x + r + 2, y + r + 2)
        grund = punkt(b, w, h, x - 3, y - 3)
        n = 0
        for dy in range(r):
            for dx in range(r):
                p = punkt(b, w, h, x + dx, y + dy)
                if p is None or p == frame or p == grund:
                    continue
                n += 1
        return n, frame, grund

    na, ra, ga = gemischt(A, wa, ha)
    nb, rb, gb = gemischt(B, wb, hb)
    print("PAINT-CORNER: corner square %dx%d at %d,%d" % (r, r, x, y))
    print("   without radius: %d blended pixels  (frame %s, background %s)"
          % (na, ra, ga))
    print("   with  radius: %d blended pixels  (frame %s, background %s)"
          % (nb, rb, gb))
    zusagen = 0
    error = 0
    if nb > na:
        print("  OK    the round corner carries %d blended pixels "
              "mehr als die eckige" % (nb - na))
        zusagen += 1
    else:
        print("  FAIL  the round corner does not carry more blended "
              "Bildpunkte als die eckige (%d gegen %d)" % (nb, na))
        error += 1
    if na * 4 < r * r:
        print("  OK    CONTROL: the square corner is blended to less than "
              "einem Viertel gemischt (%d von %d)" % (na, r * r))
        zusagen += 1
    else:
        print("  FAIL  CONTROL: the square corner is blended too "
              "(%d von %d)" % (na, r * r))
        error += 1
    print("PAINT-ECKE: %d Zusagen, %d Fehler" % (zusagen, error))
    return 1 if error else 0


def vergleich(argv):
    a, bpfad = argv[0], argv[1]
    x, y, w0, h0 = (int(v) for v in argv[2:6])
    wa, ha, ba = ppm_read(a)
    wb, hb, bb = ppm_read(bpfad)
    if (wa, ha) != (wb, hb):
        print("  FAIL  verschiedene Bildgroessen: %dx%d gegen %dx%d"
              % (wa, ha, wb, hb))
        return 1
    reach = 8
    changed = 0
    gesamt = 0
    for yy in range(max(0, y - reach), min(ha, y + h0 + reach)):
        for xx in range(max(0, x - reach), min(wa, x + w0 + reach)):
            if x <= xx < x + w0 and y <= yy < y + h0:
                continue
            gesamt += 1
            if punkt(ba, wa, ha, xx, yy) != punkt(bb, wb, hb, xx, yy):
                changed += 1
    print("PAINT-COMPARE: edge around %d,%d %dx%d (%d pixels wide)"
          % (x, y, w0, h0, reach))
    print("   %d of %d pixels differ (%.1f%%)"
          % (changed, gesamt, 100.0 * changed / gesamt if gesamt else 0))
    if changed > 0:
        print("  OK    the edge is demonstrably a different one")
        return 0
    print("  FAIL  the two runs paint the same edge -- the "
          "Schatten ist nicht da")
    return 1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    was = sys.argv[1]
    rest = sys.argv[2:]
    if was == "schatten":
        return schatten(rest)
    if was == "ecke":
        return ecke(rest)
    if was == "vergleich":
        return vergleich(rest)
    print("unbekannt: %s" % was)
    return 2


if __name__ == "__main__":
    sys.exit(main())
