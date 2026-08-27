#!/usr/bin/env python3
"""tools/icons/sheet.py -- the overview picture, rendered at the sizes
the icons are actually used at.

An icon sheet drawn at ninety-six pixels and then looked at proves
nothing.  The question is whether the outline survives SIXTEEN, which is
the size a list row and a status line give it, and the only way to find
out is to render it at sixteen and look at the pixels.  So this program
renders every icon at every size the interface uses -- and it renders
them through `tools/ttf/raster.py`, the same integer rasteriser the
kernel runs, so that what is in the picture is what will be on the
screen and not what some other library thinks the outline means.

IT DRAWS THE SAME SHEET TWICE, once dark-on-light and once
light-on-dark, out of the SAME font and the SAME outlines.  That is the
whole argument for a font over a set of bitmaps, made visible: there is
no second set of pictures anywhere, only a second colour.

And it writes a third one with the colour taken out.  An icon that only
means something because it is red is unreadable to about one man in
twelve; the grey sheet is where that shows up, because in it a warning
and an error and a success have nothing left but their outline.

PNG IS WRITTEN BY HAND, with `zlib` from the standard library and
nothing else -- same rule as `tools/ttf/subset.py` and
`tools/osum/mkfs.py`.  A picture that is evidence should not depend on
an image library being installed.

Usage:
    sheet.py [--font F] [--text F] [--list F] [--out DIR] [--sizes 16,20,24]
"""

import os
import struct
import sys
import zlib

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))
sys.path.insert(0, os.path.join(WURZEL, "tools", "ttf"))

import raster  # noqa: E402

# The two colour pairs.  THEY ARE NOT INVENTED HERE and they are not a
# theme: they are the light and the dark binding of the two roles
# `surface` and `text-primary` from round THEME's `day` scheme
# (assets/schemes/day.scheme on that branch: neutral50 / neutral900 and
# neutral900 / neutral100).  This program takes them as a picture would
# take them, to show that ONE outline serves both; the interface itself
# never writes a colour, it asks the theme.
HELL_BG = (0xF8, 0xFA, 0xFC)
HELL_FG = (0x0F, 0x17, 0x2A)
HELL_DIM = (0x47, 0x55, 0x69)
DUNKEL_BG = (0x0F, 0x17, 0x2A)
DUNKEL_FG = (0xF1, 0xF5, 0xF9)
DUNKEL_DIM = (0x94, 0xA3, 0xB8)


class Bild:
    def __init__(self, w, h, bg):
        self.w = w
        self.h = h
        self.d = bytearray()
        for _ in range(w * h):
            self.d += bytes(bg)

    def punkt(self, x, y, rgb):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        at = (y * self.w + x) * 3
        self.d[at:at + 3] = bytes(rgb)

    def hole(self, x, y):
        at = (y * self.w + x) * 3
        return tuple(self.d[at:at + 3])

    def mische(self, x, y, rgb, a):
        """The same mixing the interface does: dst + (src - dst) * a / 255."""
        if x < 0 or y < 0 or x >= self.w or y >= self.h or a == 0:
            return
        alt = self.hole(x, y)
        neu = tuple((alt[i] * (255 - a) + rgb[i] * a + 127) // 255
                    for i in range(3))
        self.punkt(x, y, neu)

    def rechteck(self, x, y, w, h, rgb):
        for r in range(h):
            for c in range(w):
                self.punkt(x + c, y + r, rgb)

    def png(self, pfad):
        roh = bytearray()
        for y in range(self.h):
            roh.append(0)                       # filter: none
            at = y * self.w * 3
            roh += self.d[at:at + self.w * 3]

        def block(marke, nutz):
            return (struct.pack(">I", len(nutz)) + marke + nutz
                    + struct.pack(">I", zlib.crc32(marke + nutz) & 0xFFFFFFFF))

        kopf = struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0)
        datei = (b"\x89PNG\r\n\x1a\n" + block(b"IHDR", kopf)
                 + block(b"IDAT", zlib.compress(bytes(roh), 9))
                 + block(b"IEND", b""))
        open(pfad, "wb").write(datei)
        return len(datei)


def glyphe_malen(bild, f, cp, px, x, y, rgb):
    """One glyph, top left at (x, y), the em box px on a side.

    The icon font's ascent is its whole em, so the baseline sits at
    y + px and the box is exactly y .. y + px.  Same arithmetic as
    `wlibc.icon_at`; if the two ever disagree the picture stops matching
    the screen, which is the point of having two of them.
    """
    gid = f.glyph_of(cp)
    if gid == 0:
        return 0
    g = raster.raster(f, gid, px)
    grund = y + px
    x0 = x + g.links
    y0 = grund - g.oben
    gesetzt = 0
    for r in range(g.h):
        for c in range(g.w):
            a = g.a[r * g.w + c]
            if a:
                bild.mische(x0 + c, y0 + r, rgb, a)
                gesetzt += 1
    return gesetzt


def text_malen(bild, f, px, x, grund, s, rgb):
    cx = x * 64
    vorher = 0
    for ch in s:
        c = ord(ch)
        gid = f.glyph_of(c)
        if vorher:
            cx += f.kern(vorher, gid) * raster.scale_of(px, f.upm) >> 10
        g = raster.raster(f, gid, px)
        x0 = (cx >> 6) + g.links
        y0 = grund - g.oben
        for r in range(g.h):
            for cc in range(g.w):
                a = g.a[r * g.w + cc]
                if a:
                    bild.mische(x0 + cc, y0 + r, rgb, a)
        cx += g.adv26
        vorher = gid
    return cx >> 6


def liste_lesen(pfad):
    aus = []
    for roh in open(pfad, encoding="ascii"):
        if roh.startswith("#") or not roh.strip():
            continue
        name, cp, herkunft = roh.rstrip("\n").split("\t")
        if herkunft.startswith("alias:"):
            continue
        aus.append((name, int(cp, 16), herkunft))
    return aus


def blatt(eintraege, ifont, tfont, sizes, bg, fg, dim, titel):
    """One sheet: per icon a row of sizes and the name."""
    spalten = 2
    je = (len(eintraege) + spalten - 1) // spalten
    zellw = 300
    zeilh = max(sizes) + 8
    rand = 16
    kopf = 34
    w = rand * 2 + zellw * spalten
    h = kopf + rand + je * zeilh
    b = Bild(w, h, bg)
    text_malen(b, tfont, 15, rand, rand + 12, titel, fg)
    x0 = rand
    for i, (name, cp, _q) in enumerate(eintraege):
        sp = i // je
        ze = i % je
        cx = x0 + sp * zellw
        cy = kopf + ze * zeilh
        for px in sizes:
            glyphe_malen(b, ifont, cp, px, cx, cy + (max(sizes) - px) // 2, fg)
            cx += px + 6
        kurz = name[5:] if name.startswith("icon.") else name
        text_malen(b, tfont, 13, cx + 4, cy + max(sizes) - 5, kurz, dim)
    return b


def main(argv):
    ifont_p = os.path.join(WURZEL, "assets", "osum-icons.ttf")
    tfont_p = os.path.join(WURZEL, "assets", "osum-sans.ttf")
    liste_p = os.path.join(WURZEL, "assets", "icons", "icons.list")
    aus_d = os.path.join(WURZEL, "docs", "icons")
    sizes = [16, 20, 24]
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--font":
            ifont_p = argv[i + 1]; i += 2
        elif a == "--text":
            tfont_p = argv[i + 1]; i += 2
        elif a == "--list":
            liste_p = argv[i + 1]; i += 2
        elif a == "--out":
            aus_d = argv[i + 1]; i += 2
        elif a == "--sizes":
            sizes = [int(x) for x in argv[i + 1].split(",")]; i += 2
        else:
            print(__doc__)
            return 2

    os.makedirs(aus_d, exist_ok=True)
    eintraege = liste_rest = liste_lesen(liste_p)
    ifont = raster.Ttf(open(ifont_p, "rb").read())
    tfont = raster.Ttf(open(tfont_p, "rb").read())
    grad = ", ".join(str(s) for s in sizes) + " px"

    fehlend = [n for n, cp, _ in eintraege if ifont.glyph_of(cp) == 0]
    if fehlend:
        for n in fehlend:
            print("sheet: no glyph for %s" % n, file=sys.stderr)
        return 1

    stuecke = [
        ("icons-light.png",
         blatt(eintraege, ifont, tfont, sizes, HELL_BG, HELL_FG, HELL_DIM,
               "Osum icons -- light, text-primary on surface, " + grad)),
        ("icons-dark.png",
         blatt(eintraege, ifont, tfont, sizes, DUNKEL_BG, DUNKEL_FG,
               DUNKEL_DIM,
               "Osum icons -- dark, the same outlines, one colour changed, "
               + grad)),
        # THE COLOURBLIND SHEET.  Everything in one grey, so that the
        # only thing left telling warning from error from success is the
        # outline.  If two of them look the same here, they mean the
        # same to a person who cannot separate the colours.
        ("icons-grey.png",
         blatt(eintraege, ifont, tfont, sizes, (0xEE, 0xEE, 0xEE),
               (0x33, 0x33, 0x33), (0x77, 0x77, 0x77),
               "Osum icons -- no colour at all: the shape has to carry it, "
               + grad)),
    ]
    for name, b in stuecke:
        n = b.png(os.path.join(aus_d, name))
        print("%s: %d x %d, %d octets"
              % (os.path.join(os.path.relpath(aus_d, WURZEL), name),
                 b.w, b.h, n))

    # THE NUMBER THAT SAYS WHETHER SIXTEEN PIXELS WORKS.  For every icon
    # at every size: how much ink there is, how much of it reaches full
    # coverage, and how much sits in the grey middle.  An icon with no
    # fully covered pixel at all is a smear, and it is named.
    print()
    print("legibility, measured through the kernel's own rasteriser:")
    print("  %-5s %6s %8s %8s %8s" % ("px", "icons", "ink", "solid", "grey%"))
    for px in sizes:
        tinte = 0
        voll = 0
        grau = 0
        blass = []
        for name, cp, _q in eintraege:
            g = raster.raster(ifont, ifont.glyph_of(cp), px)
            an = [v for v in g.a if v > 0]
            tinte += len(an)
            v = sum(1 for x in an if x >= 224)
            voll += v
            grau += sum(1 for x in an if 32 <= x <= 223)
            if v == 0:
                blass.append(name)
        print("  %-5d %6d %8d %8d %7.1f"
              % (px, len(eintraege), tinte, voll,
                 100.0 * grau / tinte if tinte else 0))
        for n in blass:
            print("        no fully covered pixel at %d px: %s" % (px, n))
    _ = liste_rest
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
