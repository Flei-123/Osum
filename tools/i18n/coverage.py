#!/usr/bin/env python3
# tools/i18n/coverage.py -- WHICH CHARACTERS DO THE SHIPPED FONTS COVER?
#
# Round I18N asks a question that has to be answered with a number, not
# with a hope: a message catalog in German is worth nothing if the font
# has no 'u' with two dots on it. This reads the `cmap` table of a
# TrueType file the same way kernel/ttf.fi does -- format 4 and format
# 12 -- and prints how many code points are mapped, per Unicode block.
#
#   python3 tools/i18n/coverage.py assets/osum-sans.ttf [--json]
#
# The block table below is short on purpose: it names the blocks a
# desktop in a Latin, Greek or Cyrillic language needs, plus the ones
# this round explicitly does NOT support, so that their absence shows up
# as a zero instead of as silence.
import sys
import json

BLOCKS = [
    (0x0020, 0x007E, "Basic Latin (printable)"),
    (0x00A0, 0x00FF, "Latin-1 Supplement"),
    (0x0100, 0x017F, "Latin Extended-A"),
    (0x0180, 0x024F, "Latin Extended-B"),
    (0x0250, 0x02AF, "IPA Extensions"),
    (0x02B0, 0x02FF, "Spacing Modifier Letters"),
    (0x0300, 0x036F, "Combining Diacritical Marks"),
    (0x0370, 0x03FF, "Greek and Coptic"),
    (0x0400, 0x04FF, "Cyrillic"),
    (0x0500, 0x052F, "Cyrillic Supplement"),
    (0x0530, 0x058F, "Armenian"),
    (0x0590, 0x05FF, "Hebrew"),
    (0x0600, 0x06FF, "Arabic"),
    (0x0700, 0x074F, "Syriac"),
    (0x0900, 0x097F, "Devanagari"),
    (0x0E00, 0x0E7F, "Thai"),
    (0x10A0, 0x10FF, "Georgian"),
    (0x1E00, 0x1EFF, "Latin Extended Additional"),
    (0x2000, 0x206F, "General Punctuation"),
    (0x20A0, 0x20CF, "Currency Symbols"),
    (0x2100, 0x214F, "Letterlike Symbols"),
    (0x2190, 0x21FF, "Arrows"),
    (0x2200, 0x22FF, "Mathematical Operators"),
    (0x2500, 0x257F, "Box Drawing"),
    (0x2580, 0x259F, "Block Elements"),
    (0x25A0, 0x25FF, "Geometric Shapes"),
    (0x2600, 0x26FF, "Miscellaneous Symbols"),
    (0x3000, 0x303F, "CJK Symbols and Punctuation"),
    (0x3040, 0x309F, "Hiragana"),
    (0x30A0, 0x30FF, "Katakana"),
    (0x4E00, 0x9FFF, "CJK Unified Ideographs"),
    (0xAC00, 0xD7AF, "Hangul Syllables"),
    (0xFB00, 0xFB4F, "Alphabetic Presentation Forms"),
    (0xFFF0, 0xFFFF, "Specials (U+FFFD lives here)"),
    (0x1F300, 0x1F5FF, "Miscellaneous Symbols and Pictographs"),
]

# The characters a German, French or Spanish surface really needs, plus
# the replacement character the UTF-8 decoder falls back to.
PROBE = ("äöüÄÖÜß"
         "éèêçàñ¿¡"
         "„“–€�")


def u16(b, o):
    return (b[o] << 8) | b[o + 1]


def u32(b, o):
    return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


def tables(b):
    out = {}
    n = u16(b, 4)
    for i in range(n):
        e = 12 + i * 16
        tag = bytes(b[e:e + 4]).decode("latin-1")
        out[tag] = (u32(b, e + 8), u32(b, e + 12))
    return out


def subtables(b, cmap):
    """Every (platform, encoding, format, offset) the file offers."""
    n = u16(b, cmap + 2)
    out = []
    for i in range(n):
        pid = u16(b, cmap + 4 + i * 8)
        eid = u16(b, cmap + 6 + i * 8)
        off = cmap + u32(b, cmap + 8 + i * 8)
        out.append((pid, eid, u16(b, off), off))
    return out


def read_fmt4(b, o):
    """Format 4 -- the Windows BMP table. Returns {codepoint: glyph}."""
    segx2 = u16(b, o + 6)
    seg = segx2 // 2
    ends = o + 14
    starts = ends + segx2 + 2
    deltas = starts + segx2
    ranges = deltas + segx2
    m = {}
    for i in range(seg):
        e = u16(b, ends + i * 2)
        s = u16(b, starts + i * 2)
        d = u16(b, deltas + i * 2)
        r = u16(b, ranges + i * 2)
        if s > e:
            continue
        for c in range(s, min(e, 0xFFFF) + 1):
            if r == 0:
                g = (c + d) & 0xFFFF
            else:
                at = ranges + i * 2 + r + (c - s) * 2
                if at + 1 >= len(b):
                    continue
                g = u16(b, at)
                if g == 0:
                    continue
                g = (g + d) & 0xFFFF
            if g != 0:
                m[c] = g
    return m


def read_fmt12(b, o):
    """Format 12 -- the segmented table that reaches past U+FFFF."""
    n = u32(b, o + 12)
    m = {}
    for i in range(n):
        g = o + 16 + i * 12
        s = u32(b, g)
        e = u32(b, g + 4)
        gi = u32(b, g + 8)
        if e < s or e - s > 0x200000:
            continue
        for c in range(s, e + 1):
            m[c] = gi + (c - s)
    return m


def coverage(path):
    b = open(path, "rb").read()
    t = tables(b)
    if "cmap" not in t:
        raise SystemExit("%s: no cmap table" % path)
    cmap = t["cmap"][0]
    subs = subtables(b, cmap)
    best4 = None
    best12 = None
    for pid, eid, fmt, off in subs:
        if fmt == 4 and (best4 is None or (pid == 3 and eid == 1)):
            best4 = off
        if fmt == 12 and (best12 is None or (pid == 3 and eid == 10)):
            best12 = off
    m = {}
    if best4 is not None:
        m.update(read_fmt4(b, best4))
    if best12 is not None:
        m.update(read_fmt12(b, best12))
    nglyph = u16(b, t["maxp"][0] + 4) if "maxp" in t else 0
    return {
        "file": path,
        "bytes": len(b),
        "glyphs_in_file": nglyph,
        "subtables": [{"platform": p, "encoding": e, "format": f}
                      for (p, e, f, _) in subs],
        "has_format4": best4 is not None,
        "has_format12": best12 is not None,
        "mapped": len(m),
        "distinct_glyphs": len(set(m.values())),
        "map": m,
    }


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    out = []
    for path in args:
        c = coverage(path)
        m = c["map"]
        blocks = []
        for lo, hi, name in BLOCKS:
            have = sum(1 for cp in range(lo, hi + 1) if cp in m)
            blocks.append({"block": name, "from": lo, "to": hi,
                           "have": have, "size": hi - lo + 1})
        c["blocks"] = blocks
        del c["map"]
        c["probe"] = {("U+%04X" % ord(ch)): (ord(ch) in m) for ch in PROBE}
        out.append(c)
    if as_json:
        print(json.dumps(out, indent=1))
        return
    for c in out:
        print("== %s" % c["file"])
        print("   %d octets, %d glyphs in the file" %
              (c["bytes"], c["glyphs_in_file"]))
        print("   cmap subtables: %s" %
              ", ".join("(%d,%d) format %d" % (s["platform"], s["encoding"],
                                               s["format"])
                        for s in c["subtables"]))
        print("   format 4: %s   format 12: %s" %
              (c["has_format4"], c["has_format12"]))
        print("   %d code points mapped, %d distinct glyphs" %
              (c["mapped"], c["distinct_glyphs"]))
        print("   blocks with something in them:")
        for b in c["blocks"]:
            if b["have"] > 0:
                print("     %-42s %5d / %5d" %
                      (b["block"], b["have"], b["size"]))
        print("   blocks that are EMPTY:")
        for b in c["blocks"]:
            if b["have"] == 0:
                print("     %-42s     0 / %5d" % (b["block"], b["size"]))
        miss = sorted(k for k, v in c["probe"].items() if not v)
        print("   probe of the characters a German surface needs: %s" %
              ("all present" if not miss else "MISSING " + " ".join(miss)))
        # EINE ZEILE FUER DEN TESTLAEUFER. Die Ausgabe darueber ist fuer
        # Menschen -- ein Laeufer, der sie mit `grep -A1` zerlegt, bricht
        # beim naechsten Wort, das sich aendert. Diese Zeile ist der
        # Vertrag: ein Name, ein Gleichheitszeichen, eine Zahl.
        def hab(name):
            for b in c["blocks"]:
                if b["block"].startswith(name):
                    return b["have"]
            return 0
        print("i18n-coverage: file=%s mapped=%d glyphs=%d octets=%d"
              " latin1=%d latin_a=%d fffd=%d missing=%d format12=%d"
              % (c["file"], c["mapped"], c["glyphs_in_file"], c["bytes"],
                 hab("Latin-1 Supplement"), hab("Latin Extended-A"),
                 hab("Specials"), len(miss),
                 1 if c["has_format12"] else 0))
        print("")


main()
