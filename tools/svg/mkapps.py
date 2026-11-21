#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import subprocess
import sys

SIZE = 72
ROW_SIZES = (44, 64)


def raster_osym(svg, size, out):
    import cairosvg
    from PIL import Image
    png = cairosvg.svg2png(url=svg, output_width=size, output_height=size)
    img = Image.open(io.BytesIO(png)).convert("RGBA")
    with open(out, "wb") as f:
        f.write(b"OSYM" + size.to_bytes(4, "little") * 2 + img.tobytes("raw", "BGRA"))


def bake_brand(root, name, d):
    src = os.path.join(root, "assets/icons/brand", name + ".svg")
    svg = os.path.join(d, "symbol.svg")
    with open(src, encoding="utf-8") as f, open(svg, "w", encoding="utf-8") as g:
        g.write(f.read())
    raster_osym(svg, SIZE, os.path.join(d, "symbol.osym"))
    for rs in ROW_SIZES:
        raster_osym(svg, rs, os.path.join(d, "symbol%d.osym" % rs))
    print("%s: brand symbol rasterized %dx%d + rows %s" % (name, SIZE, SIZE, ROW_SIZES))


def bake_svg(bake, src, d):
    svg = os.path.join(d, "symbol.svg")
    with open(src, encoding="ascii") as f, open(svg, "w", encoding="ascii") as g:
        g.write(f.read())
    for size, name in ((SIZE, "symbol.osym"),) + tuple((rs, "symbol%d.osym" % rs) for rs in ROW_SIZES):
        rc = subprocess.run([bake, svg, os.path.join(d, name), str(size)]).returncode
        if rc != 0:
            print("bake failed", src, size, rc)
            return False
    return True


def rows(table):
    for line in open(table, encoding="ascii").read().splitlines():
        if line.strip():
            yield line.split("\t")


def main(argv):
    root, bake = argv[0], argv[1]
    only = set(argv[2:])
    for app, glyph, folder in ((r[0], r[1], r[5]) for r in rows(os.path.join(root, "tools/svg/apps.tsv"))):
        if only and app not in only:
            continue
        d = os.path.join(root, folder)
        if not os.path.isdir(d):
            print("skip", app)
            continue
        if glyph.startswith("@"):
            bake_brand(root, glyph[1:], d)
            continue
        if not bake_svg(bake, os.path.join(root, "assets/icons/app", glyph.lstrip("=") + ".svg"), d):
            return 1
        print("%s: symbol.svg -> symbol.osym %dx%d + rows %s" % (app, SIZE, SIZE, ROW_SIZES))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
