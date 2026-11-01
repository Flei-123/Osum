#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/icons/build.py -- cut an icon font out of Lucide and generate
the names the code uses.

Round ICONS.  Windows draws the whole shell -- network, battery, clock,
chevrons, window buttons, menu ticks -- out of ONE font, `Segoe Fluent
Icons`, whose glyphs sit in the Unicode private use area.  A drawing
routine there does not carry a bitmap around; it sets a character in the
current text colour at the current text size.  This round does the same,
and this program is what makes the font.

WHAT IT DOES, in order:

  1. Read `assets/icons/icons.map`: name -> code point -> source glyph.
  2. Look each source glyph up in Lucide's own `font/info.json`, which
     maps an icon NAME to the code point Lucide put it at.  That file
     ships in the package; nothing here is typed in by hand.
  3. Cut those glyphs out of `lucide.ttf` and REMAP them onto the code
     points from `icons.map`.  This is the step `tools/ttf/subset.py`
     does not do -- it keeps the code points it finds.  We do not want
     Lucide's numbering as an interface: it moves between releases.
  4. Write a font with the seven tables `kernel/gfx/ttf.fi` reads, and
     nothing else.
  5. Generate `lib/icons.fi` -- the constants the kernel and Ring 3 use,
     so that no code point is ever written into drawing code.
  6. Generate `assets/icons/icons.list` -- the flat list the test
     programs and the sheet renderer walk, so they do not each parse the
     map file again.

REPRODUCIBLE AND WITHOUT A FOREIGN LIBRARY, the same rule as
`tools/ttf/subset.py` and `tools/osum/mkfs.py`: plain `struct`, no
fontTools, no FreeType.  The table writer is imported from `subset.py`
rather than written a second time -- one arrangement of a TrueType file
in this tree, not two.

Usage:
    build.py [--map FILE] [--source FILE] [--info FILE] [--out FILE]
             [--ids FILE] [--list FILE] [--quiet]
"""

import json
import os
import struct
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
ROOT_2 = os.path.dirname(os.path.dirname(HIER))
sys.path.insert(0, os.path.join(ROOT_2, "tools", "ttf"))

import subset as schnitt  # noqa: E402  -- the path has to be set first


VORGABE_MAP = os.path.join(ROOT_2, "assets", "icons", "icons.map")
VORGABE_OUT = os.path.join(ROOT_2, "assets", "osum-icons.ttf")
VORGABE_IDS = os.path.join(ROOT_2, "lib", "icons.fi")
VORGABE_LIST = os.path.join(ROOT_2, "assets", "icons", "icons.list")
VORGABE_SRC = "/root/icon-src/lucide/font/lucide.ttf"
VORGABE_INFO = "/root/icon-src/lucide/font/info.json"



class Entry_2:
    def __init__(self, name, cp, source_2):
        self.name = name
        self.cp = cp
        self.source_2 = source_2
        self.alias_von = None


def map_read(path_2):
    """-> (list of Eintrag in file order, dict name -> Eintrag)."""
    list_ = []
    nach_name = {}
    for nr, roh in enumerate(open(path_2, encoding="ascii").read().splitlines(),
                             1):
        line_3 = roh.split("#", 1)[0].strip()
        if not line_3:
            continue
        if "=" not in line_3:
            raise SystemExit("icons.map:%d: no '=' in '%s'" % (nr, roh))
        name, _, rest = line_3.partition("=")
        name = name.strip()
        parts = rest.split()
        if len(parts) != 2:
            raise SystemExit(
                "icons.map:%d: expected two words after '=', got %d"
                % (nr, len(parts)))
        if name in nach_name:
            raise SystemExit("icons.map:%d: '%s' is defined twice" % (nr, name))
        if parts[0] == "alias":
            target = nach_name.get(parts[1])
            if target is None:
                raise SystemExit(
                    "icons.map:%d: alias to unknown name '%s'" % (nr, parts[1]))
            e = Entry_2(name, target.cp, None)
            e.alias_von = target.name
        else:
            try:
                cp = int(parts[0], 16)
            except ValueError:
                raise SystemExit(
                    "icons.map:%d: '%s' is not a hex code point"
                    % (nr, parts[0]))
            if not (0xE000 <= cp <= 0xF8FF):
                raise SystemExit(
                    "icons.map:%d: %04X is outside the private use area "
                    "E000..F8FF" % (nr, cp))
            e = Entry_2(name, cp, parts[1])
        list_.append(e)
        nach_name[name] = e
    seen = {}
    for e in list_:
        if e.alias_von is None:
            if e.cp in seen:
                raise SystemExit(
                    "icons.map: %04X is used by both '%s' and '%s'"
                    % (e.cp, seen[e.cp], e.name))
            seen[e.cp] = e.name
    return list_, nach_name



def bauen(map_path, src_path, info_path_2, out_path_2, ids_path, list_path,
          leise=False):
    list_, _ = map_read(map_path)
    echte = [e for e in list_ if e.alias_von is None]

    info = json.load(open(info_path_2, encoding="utf-8"))
    v = schnitt.Vorlage(src_path)
    voll = v.cmap()

    char = {}
    fehlend = []
    for e in echte:
        satz = info.get(e.source_2)
        if satz is None:
            fehlend.append((e.name, e.source_2))
            continue
        qcp = int(satz["encodedCode"].lstrip("\\"), 16)
        gid = voll.get(qcp)
        if not gid:
            fehlend.append((e.name, e.source_2))
            continue
        char[e.cp] = gid
    if fehlend:
        for name, source_2 in fehlend:
            print("build: %s -- no glyph '%s' in the source font"
                  % (name, source_2), file=sys.stderr)
        raise SystemExit(1)

    behalten = [0]
    for gid in char.values():
        if gid not in behalten:
            behalten.append(gid)
    open_ = list(behalten)
    zusammengesetzt = 0
    while open_:
        g = open_.pop()
        parts = schnitt.komponenten(v.glyph_bytes(g))
        if parts:
            zusammengesetzt += 1
        for k in parts:
            if k not in behalten:
                behalten.append(k)
                open_.append(k)
    behalten.sort()
    karte = {alt: new for new, alt in enumerate(behalten)}

    glyf = bytearray()
    offset = []
    for alt in behalten:
        offset.append(len(glyf))
        roh = v.glyph_bytes(alt)
        if roh and schnitt.s16(roh, 0) < 0:
            roh = schnitt.komponenten_new(roh, karte)
        glyf += schnitt.pad4(roh)
    offset.append(len(glyf))
    lang = offset[-1] > 0x1FFFE
    if lang:
        loca = b"".join(struct.pack(">I", o) for o in offset)
    else:
        loca = b"".join(struct.pack(">H", o // 2) for o in offset)

    hmtx = b"".join(struct.pack(">Hh", *v.metric(alt)) for alt in behalten)

    head = bytearray(v.d[v.tab["head"][0]:v.tab["head"][0] + 54])
    struct.pack_into(">h", head, 50, 1 if lang else 0)
    struct.pack_into(">I", head, 8, 0)
    hhea = bytearray(v.d[v.tab["hhea"][0]:v.tab["hhea"][0] + 36])
    struct.pack_into(">H", hhea, 34, len(behalten))
    maxp = bytearray(v.d[v.tab["maxp"][0]:v.tab["maxp"][0] + 32])
    struct.pack_into(">H", maxp, 4, len(behalten))

    tabellen = {
        "cmap": schnitt.cmap4({c: karte[g] for c, g in char.items()}),
        "glyf": bytes(glyf),
        "head": bytes(head),
        "hhea": bytes(hhea),
        "hmtx": hmtx,
        "loca": loca,
        "maxp": bytes(maxp),
    }

    marken = sorted(tabellen)
    n = len(marken)
    suchbereich = 16
    while suchbereich * 2 <= n * 16:
        suchbereich *= 2
    entry = 0
    x = suchbereich // 16
    while x > 1:
        entry += 1
        x //= 2
    header = struct.pack(">IHHHH", 0x00010000, n, suchbereich, entry,
                       n * 16 - suchbereich)
    pos = 12 + 16 * n
    verz = b""
    koerper = b""
    for m in marken:
        d = tabellen[m]
        verz += struct.pack(">4sIII", m.encode("latin1"), schnitt.sum_(d),
                            pos, len(d))
        koerper += schnitt.pad4(d)
        pos += len(schnitt.pad4(d))
    file_2 = bytearray(header + verz + koerper)
    check = (0xB1B0AFBA - schnitt.sum_(bytes(file_2))) & 0xFFFFFFFF
    for i, m in enumerate(marken):
        if m == "head":
            hoff = schnitt.u32(file_2, 12 + 16 * i + 8)
            struct.pack_into(">I", file_2, hoff + 8, check)

    os.makedirs(os.path.dirname(out_path_2), exist_ok=True)
    open(out_path_2, "wb").write(bytes(file_2))

    source_big = os.path.getsize(src_path)
    if not leise:
        print("%s: %d names (%d glyphs, %d aliases), %d octets"
              % (os.path.relpath(out_path_2, ROOT_2), len(list_), len(echte),
                 len(list_) - len(echte), len(file_2)))
        print("   source %s: %d glyphs, %d octets"
              % (os.path.relpath(src_path, "/root"), v.numglyphs,
                 source_big))
        print("   cut to %.2f %% of the source, %d composite glyphs, "
              "upm=%d asc=%d desc=%d"
              % (100.0 * len(file_2) / source_big, zusammengesetzt, v.upm,
                 v.ascent, v.descent))
        print("   tables: %s" % ", ".join(marken))

    ids_write(ids_path, list_, echte, len(file_2), source_big, v)
    list_write(list_path, list_)
    return len(file_2), source_big, len(echte), len(list_)



def firn_name(name):
    """icon.network.no-internet -> NETWORK_NO_INTERNET."""
    short = name
    if short.startswith("icon."):
        short = short[5:]
    return short.replace(".", "_").replace("-", "_").upper()


def ids_write(path_2, list_, echte, big_2, source_big, v):
    z = []
    z.append("// SPDX-License-Identifier: GPL-2.0-only")
    z.append("// lib/icons.fi -- GENERATED by tools/icons/build.py "
             "out of assets/icons/icons.map.")
    z.append("//")
    z.append("// DO NOT EDIT.  Change the map and run the builder; the "
             "test in")
    z.append("// tools/icons/run.sh rebuilds this file and fails if it "
             "differs from")
    z.append("// what is committed.")
    z.append("//")
    z.append("// One constant per icon name.  A code point never appears "
             "in drawing")
    z.append("// code -- `tools/icons/rawcp.py` counts the ones that do, "
             "and the")
    z.append("// answer has to stay 0.  The reason is plain: 0xE041 is a "
             "number with")
    z.append("// no meaning, `icons.WINDOW_MINIMISE` is a name that can "
             "be looked up.")
    z.append("//")
    z.append("// The glyphs live in assets/osum-icons.ttf, installed as "
             "/lib/icons.ttf,")
    z.append("// cut from Lucide (ISC, assets/icons/LICENSE.lucide).  "
             "See docs/ICONS.md.")
    z.append("//")
    z.append("//   names      %d (%d glyphs, %d aliases)"
             % (len(list_), len(echte), len(list_) - len(echte)))
    z.append("//   font       %d octets, cut from %d"
             % (big_2, source_big))
    z.append("//   upm        %d, ascent %d, descent %d"
             % (v.upm, v.ascent, v.descent))
    z.append("")
    z.append("profile kernel")
    z.append("")
    z.append("export {")
    z.append("    COUNT, FIRST, LAST, UPM,")
    names = [firn_name(e.name) for e in list_]
    for i in range(0, len(names), 4):
        z.append("    " + ", ".join(names[i:i + 4]) + ",")
    z.append("    is_icon, index_of, at_index")
    z.append("}")
    z.append("")
    z.append("// How many names there are, and the range they live in. "
             "A caller that")
    z.append("// walks the whole set -- the test program, the sheet -- "
             "uses these")
    z.append("// instead of a number it typed in itself.")
    z.append("const COUNT: u64 = %d" % len(echte))
    cps = sorted(e.cp for e in list_)
    z.append("const FIRST: u64 = 0x%04X" % cps[0])
    z.append("const LAST: u64 = 0x%04X" % cps[-1])
    z.append("const UPM: u64 = %d" % v.upm)
    z.append("")
    block = None
    for e in list_:
        b = e.name.split(".")[1] if e.name.count(".") >= 2 else "general"
        if b != block:
            block = b
            z.append("")
            z.append("// --- %s" % b)
        if e.alias_von is not None:
            z.append("const %-24s: u64 = 0x%04X // = %s"
                     % (firn_name(e.name), e.cp, firn_name(e.alias_von)))
        else:
            z.append("const %-24s: u64 = 0x%04X // %s"
                     % (firn_name(e.name), e.cp, e.source_2))
    z.append("")
    z.append("// The position of an icon in the list, 0..COUNT-1, or "
             "COUNT if the")
    z.append("// code point is not one of ours.  A caller that walks all "
             "icons -- the")
    z.append("// test program, the sheet, a settings page -- needs a "
             "dense index; the")
    z.append("// code points are deliberately NOT dense, because they "
             "are an")
    z.append("// interface with room left in it.")
    z.append("//")
    z.append("// THE TOOLTIP TEXT IS NOT HERE.  It belongs in the "
             "message catalogue of")
    z.append("// round I18N under the key `<name>.tip` -- see "
             "locale/en/icons.  A")
    z.append("// name in the interface that is compiled into the "
             "drawing code cannot")
    z.append("// be translated, and an icon without a name cannot be "
             "read by anyone")
    z.append("// who does not already know what it means.")
    z.append("fn index_of(c: u64) -> u64 {")
    for i, e in enumerate(echte):
        z.append("    if c == 0x%04X { return %d }" % (e.cp, i))
    z.append("    return COUNT")
    z.append("}")
    z.append("")
    z.append("// The other way round: the code point of the icon at "
             "position `i`.")
    z.append("fn at_index(i: u64) -> u64 {")
    for i, e in enumerate(echte):
        z.append("    if i == %d { return 0x%04X }" % (i, e.cp))
    z.append("    return 0")
    z.append("}")
    z.append("")
    z.append("// Is this code point one of ours?  The drawing routine "
             "asks before it")
    z.append("// reaches for the icon font, so that a stray value ends "
             "up as a")
    z.append("// missing glyph and not as somebody else's letter.")
    z.append("fn is_icon(c: u64) -> bool {")
    z.append("    return c >= FIRST && c <= LAST")
    z.append("}")
    z.append("")
    os.makedirs(os.path.dirname(path_2), exist_ok=True)
    open(path_2, "w", encoding="ascii").write("\n".join(z))


def list_write(path_2, list_):
    """name<TAB>codepoint<TAB>source-or-alias -- for the test runners."""
    z = ["# GENERATED by tools/icons/build.py -- name, code point, origin"]
    for e in list_:
        z.append("%s\t%04X\t%s"
                 % (e.name, e.cp,
                    e.source_2 if e.alias_von is None
                    else "alias:" + e.alias_von))
    open(path_2, "w", encoding="ascii").write("\n".join(z) + "\n")


def main(argv):
    map_path, src, info = VORGABE_MAP, VORGABE_SRC, VORGABE_INFO
    out, ids, lst = VORGABE_OUT, VORGABE_IDS, VORGABE_LIST
    leise = False
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--map":
            map_path = argv[i + 1]; i += 2
        elif a == "--source":
            src = argv[i + 1]; i += 2
        elif a == "--info":
            info = argv[i + 1]; i += 2
        elif a == "--out":
            out = argv[i + 1]; i += 2
        elif a == "--ids":
            ids = argv[i + 1]; i += 2
        elif a == "--list":
            lst = argv[i + 1]; i += 2
        elif a == "--quiet":
            leise = True; i += 1
        else:
            print(__doc__)
            return 2
    if not os.path.exists(src):
        print("build: the Lucide font is not at %s.\n"
              "       Unpack lucide-static there, or pass --source." % src,
              file=sys.stderr)
        return 1
    bauen(map_path, src, info, out, ids, lst, leise)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
