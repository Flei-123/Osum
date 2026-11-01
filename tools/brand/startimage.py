#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only

import sys
from PIL import Image

GROESSEN = [16, 24, 32, 48, 64]


def load(path_2, n):
    im = Image.open(path_2).convert("RGBA")
    if im.size != (n, n):
        im = im.resize((n, n), Image.LANCZOS)
    return im


def worte(im):
    out = []
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = im.getpixel((x, y))
            out.append((a << 24) | (r << 16) | (g << 8) | b)
    return out


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else "assets/marke"
    target = sys.argv[2] if len(sys.argv) > 2 else "kernel/user/brand_start.fi"
    t = []
    t.append("// SPDX-License-Identifier: GPL-2.0-only\n")
    t.append("// kernel/user/brand_start.fi -- ERZEUGT, NICHT VON HAND\n")
    t.append("//   tools/brand/startimage.py assets/marke "
             "kernel/user/brand_start.fi\n")
    t.append("//\n")
    t.append("// Das Startzeichen von Osum als Bildpunkte, in\n")
    t.append("// mehreren Groessen, je Bildpunkt ein Wort 0xAARRGGBB.\n")
    t.append("// Warum es hier\n")
    t.append("// steht und nicht in der Symbolschrift oder in einer Datei,\n")
    t.append("// steht im Kopf von tools/brand/startimage.py.\n\n")
    t.append("profile kernel\n\n")
    t.append("export { breit, punkt }\n\n")
    for n in GROESSEN:
        im = load("%s/start-%d.png" % (source, n), n)
        w = worte(im)
        t.append("static mut b%d: [u64; %d] = [\n" % (n, len(w)))
        line = "    "
        for i, v in enumerate(w):
            s = "%d as u64" % v
            if i + 1 < len(w):
                s += ","
            if len(line) + len(s) > 72:
                t.append(line + "\n")
                line = "    "
            line += s + " "
        t.append(line.rstrip() + "\n]\n\n")
    t.append("// Welche Groesse fuer eine gewuenschte Kantenlaenge\n")
    t.append("// genommen wird: die groesste, die noch hineinpasst. Ein Ring\n")
    t.append("// von einem Bildpunkt Staerke vertraegt keine Interpolation.\n")
    t.append("fn breit(wunsch: u64) -> u64 {\n")
    for n in reversed(GROESSEN):
        t.append("    if wunsch >= %d {\n        return %d\n    }\n" % (n, n))
    t.append("    return %d\n}\n\n" % GROESSEN[0])
    t.append("// Ein Bildpunkt, 0xAARRGGBB. Ausserhalb: durchsichtig.\n")
    t.append("fn punkt(n: u64, x: u64, y: u64) -> u64 {\n")
    t.append("    if x >= n || y >= n {\n        return 0\n    }\n")
    t.append("    let i: u64 = y * n + x\n")
    for n in GROESSEN:
        t.append("    if n == %d {\n        return b%d[(i) as usize]\n    }\n"
                 % (n, n))
    t.append("    return 0\n}\n")
    open(target, "w").write("".join(t))
    print("%s geschrieben (%d Groessen)" % (target, len(GROESSEN)))


main()
