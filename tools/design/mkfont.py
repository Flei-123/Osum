#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys
import itertools
from fontTools import subset
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._k_e_r_n import KernTable_format_0
import uharfbuzz as hb


def main():
    src, dst, tmpl = sys.argv[1], sys.argv[2], sys.argv[3]
    if tmpl.endswith('.cps'):
        cps = sorted(int(l.split()[0], 16) for l in open(tmpl) if l.strip() and not l.startswith('#'))
    else:
        cps = sorted(TTFont(tmpl).getBestCmap().keys())
    blob = hb.Blob.from_file_path(src)
    face = hb.Face(blob)
    font = hb.Font(face)
    orig = TTFont(src)
    cmap = orig.getBestCmap()
    adv = {cp: orig['hmtx'][cmap[cp]][0] for cp in cps if cp in cmap}
    names = {cp: cmap[cp] for cp in cps if cp in cmap}
    pairs = {}
    chars = [cp for cp in cps if cp in cmap and cp > 32]
    for a in chars:
        for b in chars:
            buf = hb.Buffer()
            buf.add_str(chr(a) + chr(b))
            buf.guess_segment_properties()
            hb.shape(font, buf, {"kern": True, "liga": False, "calt": False})
            infos = buf.glyph_infos
            pos = buf.glyph_positions
            if len(infos) != 2:
                continue
            d = pos[0].x_advance - adv[a]
            if d != 0:
                pairs[(names[a], names[b])] = d
    opts = subset.Options()
    opts.layout_features = []
    opts.hinting = False
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.name_IDs = []
    opts.drop_tables += ['GPOS', 'GSUB', 'GDEF', 'OS/2', 'post', 'name', 'gasp',
                         'cvt ', 'fpgm', 'prep', 'DSIG', 'STAT', 'avar', 'fvar']
    ss = subset.Subsetter(opts)
    f = TTFont(src, recalcTimestamp=False)
    ss.populate(unicodes=cps)
    ss.subset(f)
    keep = {'cmap', 'glyf', 'head', 'hhea', 'hmtx', 'loca', 'maxp'}
    for t in list(f.keys()):
        if t not in keep and t != 'GlyphOrder':
            del f[t]
    for cp, gname in ((0xAD, 'hyphen'), (0x149, 'n'), (0xFFFD, 'question')):
        if cp in cps and gname in f.getGlyphOrder():
            for t in f['cmap'].tables:
                if t.isUnicode():
                    t.cmap[cp] = gname
    have = set(f.getGlyphOrder())
    kt = KernTable_format_0()
    kt.version = 0
    kt.coverage = 1
    kt.format = 0
    allp = [(abs(v), k, v) for k, v in pairs.items() if k[0] in have and k[1] in have]
    allp.sort(key=lambda t: (-t[0], t[1]))
    allp = allp[:10900]
    kt.kernTable = {k: v for _a, k, v in allp}
    kern = newTable('kern')
    kern.version = 0
    kern.kernTables = [kt]
    f['kern'] = kern
    f['head'].created = f['head'].modified = 3849000000
    f.save(dst)
    print("%s: %d glyphs, %d kern pairs, %d bytes" % (
        dst, len(have), len(kt.kernTable), len(open(dst, 'rb').read())))


if __name__ == '__main__':
    main()
