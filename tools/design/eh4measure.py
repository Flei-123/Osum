#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import glob
import os
import re
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    print("PIL fehlt", file=sys.stderr)
    sys.exit(2)

HIER = os.path.dirname(os.path.abspath(__file__))


def serial(d):
    p = os.path.join(d, "serial.txt")
    if not os.path.exists(p):
        return ""
    return open(p, "rb").read().decode("latin1", "replace")


def last_2(t, muster):
    m = None
    for m in re.finditer(muster, t):
        pass
    return m


def flaechenfarben(im, n=6):
    k = im.getcolors(maxcolors=1 << 24) or []
    k.sort(reverse=True)
    ges = sum(a for (a, _) in k) or 1
    return [(c, a * 100.0 / ges) for (a, c) in k[:n]]


def blaustich(im):
    tot = 0.0
    gew = 0.0
    for (c, p) in flaechenfarben(im, 8):
        tot += (c[2] - c[0]) * p
        gew += p
    return tot / gew if gew else 0.0


def kasten_der_tinte(im, cx, cy, r, tol=40):
    x0 = max(0, cx - r)
    y0 = max(0, cy - r)
    x1 = min(im.width, cx + r)
    y1 = min(im.height, cy + r)
    aus = im.crop((x0, y0, x1, y1))
    px = aus.load()
    zaehl = {}
    for y in range(aus.height):
        for x in range(aus.width):
            zaehl[px[x, y]] = zaehl.get(px[x, y], 0) + 1
    bg = max(zaehl.items(), key=lambda kv: kv[1])[0]
    xs, ys, n = [], [], 0
    for y in range(aus.height):
        for x in range(aus.width):
            c = px[x, y]
            if (abs(c[0] - bg[0]) + abs(c[1] - bg[1])
                    + abs(c[2] - bg[2])) > tol:
                xs.append(x)
                ys.append(y)
                n += 1
    if not xs:
        return None, bg, 0
    return (x0 + min(xs), y0 + min(ys), x0 + max(xs), y0 + max(ys)), bg, n


def lupe(source, target, box, factor=6):
    im = Image.open(source).convert("RGB")
    x0, y0, x1, y1 = box
    x0 = max(0, x0)
    y0 = max(0, y0)
    x1 = min(im.width, x1)
    y1 = min(im.height, y1)
    aus = im.crop((x0, y0, x1, y1))
    aus = aus.resize((aus.width * factor, aus.height * factor),
                     Image.NEAREST)
    aus.save(target)
    return target


def unterschied(a, b):
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return None
    pa, pb = ia.load(), ib.load()
    n = 0
    xs, ys = [], []
    for y in range(ia.height):
        for x in range(ia.width):
            if pa[x, y] != pb[x, y]:
                n += 1
                xs.append(x)
                ys.append(y)
    if not xs:
        return (0, None)
    return (n, (min(xs), min(ys), max(xs), max(ys)))


def part_taskbar(out, name, uisc):
    d = os.path.join(out, name)
    bd = os.path.join(out, "bilder", name)
    t = serial(d)
    print("")
    print("=" * 68)
    print("LAUF %s   (erwartete Vervielfachung %d)" % (name, uisc))
    print("=" * 68)
    if not t:
        print("  no serial output -- the run did not run")
        return
    m = last_2(t, r"taskbar: geom edge=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
    if not m:
        print("  the bar reported no geometry")
        return
    bx, by, bw, bh = (int(m.group(i)) for i in (2, 3, 4, 5))
    soll = 40 * uisc
    print("  LEISTE  x=%d y=%d %dx%d" % (bx, by, bw, bh))
    print("          Regel: Leistenhoehe = 40 * uiscale = %d" % soll)
    if abs(bh - soll) > 6:
        print("          VIOLATED: %d instead of %d -- the run did NOT"
              " Vervielfachung %d gerendert" % (bh, soll, uisc))
    else:
        print("          gehalten (%d, Abweichung %d)" % (bh, bh - soll))
    print("  SYMBOLS in the bar (from `taskbar: sym`)")
    seen = {}
    for m in re.finditer(r"taskbar: sym btn=(\d+) app=(\S*) w=(\d+)"
                         r" gemalt=(\d+) button=(\d+)", t):
        seen[int(m.group(1))] = (m.group(2), int(m.group(3)),
                                    int(m.group(4)), int(m.group(5)))
    if not seen:
        print("    none reported (no window in the bar?)")
    for i in sorted(seen):
        app, w, gem, button = seen[i]
        pro = gem * 100 // button if button else 0
        brand = "ok" if 55 <= pro <= 75 else "VERLETZT"
        print("    btn %d %-14s Datei %d, gemalt %d, Knopf %d"
              "  ->  %d%% der Knopfhoehe  %s"
              % (i, app, w, gem, button, pro, brand))
    felder = {}
    for m in re.finditer(r"taskbar: btn i=(\d+) id=\d+ x=(-?\d+) y=(-?\d+)"
                         r" w=(\d+) h=(\d+)", t):
        felder[int(m.group(1))] = tuple(int(m.group(i)) for i in (2, 3, 4, 5))
    image = os.path.join(bd, "01-schreibtisch.png")
    if felder and os.path.exists(image):
        args = [sys.executable, os.path.join(HIER, "ausrichtung.py"), image,
                "--only-measure", "--margin-bottom", str(4 * uisc)]
        for i in sorted(felder):
            x, y, w, h = felder[i]
            args.append("--field")
            args.append("%d,%d,%d,%d:btn%d" % (bx + x, by + y, w, h, i))
        m2 = last_2(t, r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
        if m2:
            args.append("--field")
            args.append("%d,%d,%s,%s:start"
                        % (bx + int(m2.group(1)), by + int(m2.group(2)),
                           m2.group(3), m2.group(4)))
        print("  AUSRICHTUNG (tools/design/ausrichtung.py)")
        r = subprocess.run(args, capture_output=True, text=True)
        for z in r.stdout.splitlines():
            print("    " + z)
    print("  BLAUSTICH B-R der Flaechenfarben (Windows/GNOME dunkel: 0,"
          " KDE: +6, Slate: +27)")
    for p in sorted(glob.glob(os.path.join(bd, "*.png"))):
        im = Image.open(p).convert("RGB")
        b = blaustich(im)
        fl = flaechenfarben(im, 3)
        toene = " ".join("#%02x%02x%02x(%.0f%%)" % (c[0], c[1], c[2], pz)
                         for (c, pz) in fl)
        brand = ""
        if name.startswith("dunkel") and b > 8:
            brand = "  VERLETZT: nicht neutral"
        print("    %-22s B-R %+5.1f   %s%s"
              % (os.path.basename(p), b, toene, brand))


def part_menu(out):
    bd = os.path.join(out, "bilder", "menue-2560")
    print("")
    print("=" * 68)
    print("START MENU -- does it appear only on demand?")
    print("=" * 68)
    seq = ["01-ohne-menue", "02-super-offen", "03-escape-weg",
             "04-logo-offen", "05-klick-daneben-weg"]
    pfade = [os.path.join(bd, f + ".png") for f in seq]
    for p in pfade:
        if not os.path.exists(p):
            print("  fehlt: %s" % os.path.basename(p))
            return
    reason = pfade[0]
    for i, p in enumerate(pfade):
        r = unterschied(reason, p)
        if r is None:
            print("  %s: andere Groesse" % seq[i])
            continue
        n, k = r
        soll_open = seq[i] in ("02-super-offen", "04-logo-offen")
        ok = (n > 20000) if soll_open else (n < 20000)
        print("  %-22s %8d pixels differ from 01   box %s   %s"
              % (seq[i], n, k, "erwartet" if ok else "VERLETZT"))
    print("  reading: 02 and 04 must differ STRONGLY from 01"
          " (das Menue steht da),")
    print("          03 and 05 hardly at all (it is gone again).")


def part_cursor(out):
    print("")
    print("=" * 68)
    print("MAUSZEIGER -- Groesse, Kantenglaettung, Lage")
    print("=" * 68)
    for name, uisc, wo in (("zeiger-1280", 1, (700, 240)),
                           ("zeiger-2560", 2, (700, 240)),
                           ("zeigerd-2560", 2, (700, 240))):
        bd = os.path.join(out, "bilder", name)
        p = os.path.join(bd, "01-zeiger-schreibtisch.png")
        if not os.path.exists(p):
            print("  %s: fehlt" % name)
            continue
        im = Image.open(p).convert("RGB")
        k, bg, n = kasten_der_tinte(im, wo[0], wo[1], 70)
        if k is None:
            print("  %s: nothing at %s -- no pointer in the image"
                  % (name, wo))
            continue
        w = k[2] - k[0] + 1
        h = k[3] - k[1] + 1
        soll_w = 16 * uisc
        soll_h = 24 * uisc
        print("  %-14s Zeigertinte %dx%d Bildpunkte bei %d,%d"
              "  (Feld %d, Pfeil erwartet rund %dx%d)"
              % (name, w, h, k[0], k[1], 24 * uisc, soll_w, soll_h))
        aus = im.crop((k[0], k[1], k[2] + 1, k[3] + 1))
        toene = len(aus.getcolors(maxcolors=1 << 24) or [])
        print("                 %d verschiedene Toene im Zeigerkasten"
              " (Bitmaske: 2)   %s"
              % (toene, "geglaettet" if toene > 8 else "VERLETZT: hart"))
        target = os.path.join(bd, "lupe-01-zeiger.png")
        lupe(p, target, (k[0] - 4, k[1] - 4, k[2] + 5, k[3] + 5), 8)
        print("                 Lupe: %s" % target)


def main():
    out = sys.argv[1]
    print("BEFUND RUNDE ECHTHARDWARE-4")
    print("Verzeichnis: %s" % out)
    for name, uisc in (("hell-1280", 1), ("hell-2560", 2),
                       ("dunkel-1280", 1), ("dunkel-2560", 2)):
        part_taskbar(out, name, uisc)
    part_menu(out)
    part_cursor(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
