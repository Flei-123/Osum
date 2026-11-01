#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SYMBOL_RANGES = [
    (0x0100, 0x02FF),
    (0x0370, 0x03FF),
    (0x0400, 0x052F),
    (0x2010, 0x205E),
    (0x2070, 0x209F),
    (0x20A0, 0x20CF),
    (0x2100, 0x218F),
    (0x2190, 0x23FF),
    (0x2500, 0x25FF),
    (0x2600, 0x27BF),
    (0x27C0, 0x27EF),
    (0x27F0, 0x27FF),
    (0x2800, 0x28FF),
    (0x2900, 0x297F),
    (0x2B00, 0x2B1F),
]
EMOJI_BMP = [(0x2190, 0x21FF), (0x2300, 0x23FF), (0x25A0, 0x25FF), (0x2600, 0x27BF), (0x2900, 0x297F), (0x2B00, 0x2BFF),
             (0x3030, 0x3030), (0x303D, 0x303D), (0x3297, 0x3299), (0x00A9, 0x00AE), (0x203C, 0x203C), (0x2049, 0x2049),
             (0x2122, 0x2139), (0x24C2, 0x24C2)]
EMOJI_ASTRAL = [(0x1F300, 0x1F64F), (0x1F680, 0x1F6FF), (0x1F900, 0x1F9FF)]
EMOJI_GRID = 4
MAX_POINTS = 1300


def cut(font, cps, keep_extra=()):
    opts = subset.Options()
    opts.layout_features = []
    opts.hinting = False
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.name_IDs = []
    opts.legacy_kern = False
    opts.drop_tables += ['GPOS', 'GSUB', 'GDEF', 'OS/2', 'post', 'name', 'gasp', 'cvt ', 'fpgm', 'prep', 'DSIG',
                         'STAT', 'avar', 'fvar', 'gvar', 'HVAR', 'VVAR', 'MATH', 'FFTM', 'kern', 'vhea', 'vmtx']
    ss = subset.Subsetter(opts)
    ss.populate(unicodes=sorted(cps))
    ss.subset(font)
    keep = {'cmap', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp'}
    for t in list(font.keys()):
        if t not in keep and t != 'GlyphOrder':
            del font[t]
    font['head'].created = font['head'].modified = 3849000000


def inrange(cp, ranges):
    return any(a <= cp <= b for a, b in ranges)


def main():
    dejavu, noto, sans, out_sym, out_emo = sys.argv[1:6]
    have = set(TTFont(sans).getBestCmap().keys())
    dj = TTFont(dejavu, recalcTimestamp=False)
    djmap = dj.getBestCmap()
    sym = {cp for cp in djmap if inrange(cp, SYMBOL_RANGES) and cp not in have}
    cut(dj, sym)
    dj.save(out_sym)
    print("%s: %d code points, %d bytes" % (out_sym, len(sym), len(open(out_sym, 'rb').read())))

    var = TTFont(noto, recalcTimestamp=False)
    var = instancer.instantiateVariableFont(var, {'wght': 400})
    nmap = var.getBestCmap()
    emo = {cp for cp in nmap
           if (inrange(cp, EMOJI_ASTRAL) or inrange(cp, EMOJI_BMP)) and cp not in have and cp not in sym}
    gl = var['glyf']
    emo = {cp for cp in emo if not (gl[nmap[cp]].numberOfContours > 0 and len(gl[nmap[cp]].coordinates) > MAX_POINTS)}
    cut(var, emo)
    g = var['glyf']
    for n in var.getGlyphOrder():
        gl = g[n]
        if gl.numberOfContours > 0:
            co = gl.coordinates
            for i in range(len(co)):
                x, y = co[i]
                co[i] = (round(x / EMOJI_GRID) * EMOJI_GRID, round(y / EMOJI_GRID) * EMOJI_GRID)
            gl.recalcBounds(g)
    var.save(out_emo)
    print("%s: %d code points, %d bytes" % (out_emo, len(emo), len(open(out_emo, 'rb').read())))


if __name__ == '__main__':
    main()
