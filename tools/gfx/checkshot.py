import re
import sys


def read_ppm(path):
    raw = open(path, "rb").read()
    if not raw.startswith(b"P6"):
        raise ValueError("not a P6 PPM: %s" % path)
    fields = []
    i = 2
    while len(fields) < 3:
        while i < len(raw) and raw[i:i + 1].isspace():
            i += 1
        if raw[i:i + 1] == b"#":
            while i < len(raw) and raw[i] != 0x0A:
                i += 1
            continue
        j = i
        while j < len(raw) and not raw[j:j + 1].isspace():
            j += 1
        fields.append(int(raw[i:j]))
        i = j
    i += 1
    b, h, _ = fields
    return b, h, raw[i:i + b * h * 3]


class Image:
    def __init__(self, path):
        self.b, self.h, self.d = read_ppm(path)

    def pixel(self, x, y):
        if x < 0 or y < 0 or x >= self.b or y >= self.h:
            return None
        o = (y * self.b + x) * 3
        return (self.d[o], self.d[o + 1], self.d[o + 2])


FIRST = 0x20
LAST = 0x7E
HEIGHT = 16
WIDTH = 8


def font_from_firn(path):
    source = open(path, "r", encoding="utf-8").read()
    pieces = re.findall(r'var b: \[u8; \d+\] = b"((?:\\x[0-9a-fA-F]{2})+)"',
                         source)
    data = bytearray()
    for s in pieces:
        data += bytes(int(v, 16)
                       for v in re.findall(r"\\x([0-9a-fA-F]{2})", s))
    return bytes(data)


def font_from_rust(path):
    source = open(path, "r", encoding="utf-8").read()
    rows = re.findall(r"\[((?:0x[0-9a-fA-F]{2},\s*){15}0x[0-9a-fA-F]{2})\]",
                        source)
    data = bytearray()
    for z in rows:
        data += bytes(int(v, 16)
                       for v in re.findall(r"0x([0-9a-fA-F]{2})", z))
    return bytes(data)


def glyph(font, char):
    c = char
    if c < FIRST or c > LAST:
        c = 0x3F
    i = (c - FIRST) * HEIGHT
    return font[i:i + HEIGHT]


class Console:
    def __init__(self, columns, rows):
        self.cols = columns
        self.rows = rows
        self.grid = [[None] * columns for _ in range(rows)]
        self.x = 0
        self.y = 0

    def scroll(self):
        self.grid.pop(0)
        self.grid.append([None] * self.cols)

    def wrap(self):
        self.x = 0
        self.y += 1
        if self.y >= self.rows:
            self.scroll()
            self.y = self.rows - 1

    def advance(self):
        self.x += 1
        if self.x >= self.cols:
            self.wrap()

    def char(self, c):
        self.grid[self.y][self.x] = c
        self.advance()

    def put(self, c):
        if c == 10:
            self.wrap()
            return
        if c == 13:
            self.x = 0
            return
        if c == 8:
            if self.x > 0:
                self.x -= 1
                self.grid[self.y][self.x] = 32
            return
        if c == 9:
            for _ in range(8 - (self.x & 7)):
                self.char(32)
            return
        self.char(c)

    def text(self, octets):
        for c in octets:
            self.put(c)


FG = (200, 208, 216)
BG = (0, 0, 0)


def color_at(args, i):
    return (int(args[i]), int(args[i + 1]), int(args[i + 2]))


def check_row(image, font, row, column, text, fg, bg):
    wrong = 0
    total = 0
    for k, char in enumerate(text):
        g = glyph(font, char)
        for r in range(HEIGHT):
            bits = g[r]
            for c in range(WIDTH):
                x = (column + k) * WIDTH + c
                y = row * HEIGHT + r
                expected = fg if (bits >> (7 - c)) & 1 else bg
                total += 1
                if image.pixel(x, y) != expected:
                    wrong += 1
    return total, wrong


def recognize(image, font, row_y, col_x, fg=None, bg=None):
    fg = FG if fg is None else fg
    bg = BG if bg is None else bg
    best = None
    best_diff = 1 << 30
    for c in range(FIRST, LAST + 1):
        _, f = check_row(image, font, row_y, col_x, bytes([c]), fg, bg)
        if f < best_diff:
            best_diff = f
            best = c
            if f == 0:
                break
    return best, best_diff


def visible(c):
    if c is None:
        return "?"
    if c == 0x20:
        return "_"
    return chr(c)


MAX_REPORTED = 16


def report(image, font, cases, fg=None, bg=None):
    bad_cells = []
    for row_y, col_x, expected in cases:
        _, f = check_row(image, font, row_y, col_x, bytes([expected]), fg or FG,
                             bg or BG)
        if f:
            actual, actual_diff = recognize(image, font, row_y, col_x, fg, bg)
            bad_cells.append((row_y, col_x, expected, actual, actual_diff, f))
    if not bad_cells:
        return
    print("  %d differing cells:" % len(bad_cells))
    for row_y, col_x, expected, actual, actual_diff, f in bad_cells[:MAX_REPORTED]:
        how = "'%s'" % visible(actual) if actual_diff == 0 else \
              "something else (closest '%s', %d pixels off)" \
              % (visible(actual), actual_diff)
        print("    row %d column %d: expected '%s' (0x%02X), actual %s"
              " -- %d pixels wrong"
              % (row_y, col_x, visible(expected), expected, how, f))
    if len(bad_cells) > MAX_REPORTED:
        print("    ... and %d more" % (len(bad_cells) - MAX_REPORTED))


def cmd_size(a):
    image = Image(a[0])
    print("%d %d" % (image.b, image.h))
    if len(a) >= 3 and (image.b, image.h) != (int(a[1]), int(a[2])):
        return 1
    return 0


def cmd_pixel(a):
    image = Image(a[0])
    p = image.pixel(int(a[1]), int(a[2]))
    if p is None:
        print("outside the image")
        return 1
    print("%d %d %d" % p)
    if len(a) >= 6 and p != color_at(a, 3):
        return 1
    return 0


def cmd_area(a):
    image = Image(a[0])
    x, y, b, h = (int(v) for v in a[1:5])
    expected = color_at(a, 5)
    wrong = 0
    for yy in range(y, y + h):
        for xx in range(x, x + b):
            if image.pixel(xx, yy) != expected:
                wrong += 1
    print("%d of %d pixels wrong" % (wrong, b * h))
    return 0 if wrong == 0 else 1


def cmd_nonblank(a):
    image = Image(a[0])
    x, y, b, h = (int(v) for v in a[1:5])
    n = 0
    for yy in range(y, y + h):
        for xx in range(x, x + b):
            p = image.pixel(xx, yy)
            if p is not None and p != BG:
                n += 1
    print("%d" % n)
    return 0 if n >= (int(a[5]) if len(a) >= 6 else 0) else 1


def cmd_text(a):
    image = Image(a[0])
    font = font_from_firn(a[1])
    text = a[4].encode("ascii", "replace")
    fg = color_at(a, 5) if len(a) >= 8 else FG
    bg = color_at(a, 8) if len(a) >= 11 else BG
    row, column = int(a[2]), int(a[3])
    total, wrong = check_row(image, font, row, column, text, fg, bg)
    print("%d pixels checked, %d wrong" % (total, wrong))
    if wrong:
        report(image, font,
                [(row, column + k, c) for k, c in enumerate(text)], fg, bg)
    return 0 if wrong == 0 else 1


def cmd_console(a):
    image = Image(a[0])
    font = font_from_firn(a[1])
    raw = open(a[2], "rb").read()
    min_cells = int(a[5]) if len(a) >= 6 else 500

    i = raw.find(a[3].encode())
    if i < 0:
        print("start marker '%s' missing in the capture" % a[3])
        return 1
    j = raw.find(a[4].encode(), i)
    if j < 0:
        print("end marker '%s' missing in the capture" % a[4])
        return 1
    j = raw.find(b"\n", j)
    j = len(raw) if j < 0 else j + 1

    k = Console(image.b // WIDTH, image.h // HEIGHT)
    k.text(raw[i:j])

    wrong = 0
    total = 0
    cells = 0
    cases = []
    for row_y in range(k.rows):
        for col_x in range(k.cols):
            c = k.grid[row_y][col_x]
            if c is None:
                continue
            cells += 1
            cases.append((row_y, col_x, c))
            g, f = check_row(image, font, row_y, col_x, bytes([c]), FG, BG)
            total += g
            wrong += f
    print("%d cells, %d pixels, %d wrong" % (cells, total, wrong))
    if cells < min_cells:
        print("  too few cells -- the capture did not reach the screen")
        return 1
    if wrong:
        report(image, font, cases)
    return 0 if wrong == 0 else 1


def cmd_find(a):
    image = Image(a[0])
    font = font_from_firn(a[1])
    raw = open(a[2], "rb").read()
    needle = a[5].encode()

    i = raw.find(a[3].encode())
    if i < 0:
        print("start marker '%s' missing in the capture" % a[3])
        return 1
    j = raw.find(a[4].encode(), i)
    if j < 0:
        print("end marker '%s' missing in the capture" % a[4])
        return 1
    j = raw.find(b"\n", j)
    j = len(raw) if j < 0 else j + 1

    k = Console(image.b // WIDTH, image.h // HEIGHT)
    k.text(raw[i:j])

    for row_y in range(k.rows):
        row = bytes((c if c is not None else 32) for c in k.grid[row_y])
        p = row.find(needle)
        if p >= 0:
            g, f = check_row(image, font, row_y, p, needle, FG, BG)
            print("row %d, column %d: %d pixels, %d wrong"
                  % (row_y, p, g, f))
            if f:
                report(image, font,
                        [(row_y, p + i, c) for i, c in enumerate(needle)])
            return 0 if f == 0 else 1
    print("'%s' is not on the reconstructed screen" % a[5])
    return 1


def cmd_font(a):
    fi = font_from_firn(a[0])
    expected = (LAST - FIRST + 1) * HEIGHT
    if len(fi) != expected:
        print("kernel/gfx/font.fi has %d octets, expected %d" % (len(fi), expected))
        return 1
    if len(a) < 2:
        print("%d octets, 95 glyphs (reference missing)" % len(fi))
        return 0
    rust_font = font_from_rust(a[1])
    if len(rust_font) != len(fi):
        print("reference %d octets, port %d" % (len(rust_font), len(fi)))
        return 1
    differing = sum(1 for x, y in zip(fi, rust_font) if x != y)
    print("%d octets against the Rust reference, %d different"
          % (len(fi), differing))
    return 0 if differing == 0 else 1


def cmd_read(a):
    image = Image(a[0])
    font = font_from_firn(a[1])
    start = int(a[2]) if len(a) >= 3 else 0
    count = int(a[3]) if len(a) >= 4 else image.h // HEIGHT - start
    patterns = {}
    for c in range(FIRST, LAST + 1):
        patterns.setdefault(bytes(glyph(font, c)), c)
    print("%dx%d, %d columns, %d rows"
          % (image.b, image.h, image.b // WIDTH, image.h // HEIGHT))
    for row_y in range(start, min(start + count, image.h // HEIGHT)):
        row = []
        for col_x in range(image.b // WIDTH):
            bits = []
            foreign = False
            for r in range(HEIGHT):
                v = 0
                for c in range(WIDTH):
                    p = image.pixel(col_x * WIDTH + c, row_y * HEIGHT + r)
                    if p == FG:
                        v |= 1 << (7 - c)
                    elif p != BG:
                        foreign = True
                bits.append(v)
            if foreign:
                row.append("#")
            elif bytes(bits) in patterns:
                row.append(chr(patterns[bytes(bits)]))
            elif any(bits):
                row.append("~")
            else:
                row.append(" ")
        print("%3d |%s|" % (row_y, "".join(row)))
    return 0


def _load_raster():
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.join(here, "..", "ttf"))
    import raster
    return _InkChooser(raster)


class _InkChooser:

    def __init__(self, raster):
        self.r = raster

    def Schrift(self, path, px):
        if path.startswith("fui:"):
            import fuiraster
            return fuiraster.Schrift(path[4:], px)
        return self.r.Schrift(path, px)


def blend(old, new, a):
    if a == 0:
        return old
    if a >= 255:
        return new
    ia = 255 - a
    return tuple((old[k] * ia + new[k] * a + 127) // 255 for k in range(3))


def _check_glyphs(image, face, places, baseline_y, fg, bg, tolerance,
                    width=0):
    char = 0
    ink_count = 0
    wrong = 0
    empty = []
    bad_cells = []
    for (c, gx, gy) in places:
        g = face.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        lo = gx if width else None
        hi = gx + width if width else None
        char += 1
        set_count = 0
        hit = 0
        bad_count = 0
        for r in range(g.h):
            for k in range(g.w):
                a = g.punkt(k, r)
                if a == 0:
                    continue
                px = gx + g.links + k
                py = gy - g.oben + r
                if lo is not None and (px < lo or px >= hi):
                    continue
                set_count += 1
                expected = blend(bg, fg, a)
                actual = image.pixel(px, py)
                if actual is None:
                    bad_count += 1
                    continue
                if max(abs(actual[j] - expected[j]) for j in range(3)) <= tolerance:
                    hit += 1
                else:
                    bad_count += 1
        ink_count += set_count
        wrong += bad_count
        ink_in_image = 0
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) == 0:
                    continue
                if lo is not None:
                    if gx + g.links + k < lo or gx + g.links + k >= hi:
                        continue
                actual = image.pixel(gx + g.links + k, gy - g.oben + r)
                if actual is not None and actual != bg:
                    ink_in_image += 1
        if set_count > 0 and ink_in_image == 0:
            empty.append(visible(c))
        if bad_count and len(bad_cells) < 8:
            bad_cells.append("'%s' at x=%d: %d of %d ink pixels wrong"
                            % (visible(c), gx, bad_count, set_count))
    return char, ink_count, wrong, empty, bad_cells


def cmd_tchain(a):
    raster = _load_raster()
    image = Image(a[0])
    face = raster.Schrift(a[1], int(a[2]))
    x, y = int(a[3]), int(a[4])
    fg = (int(a[5]), int(a[6]), int(a[7]))
    bg = (int(a[8]), int(a[9]), int(a[10]))
    text = a[11]
    tol = int(a[12]) if len(a) > 12 else 0
    ymax = int(a[13]) if len(a) > 13 else None
    places = [(c, x + (dx >> 6), y) for (c, dx) in face.stellen(text)]

    expected = {}
    for (c, gx, gy) in places:
        g = face.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        for r in range(g.h):
            for k in range(g.w):
                d = g.punkt(k, r)
                if d == 0:
                    continue
                px = gx + g.links + k
                py = gy - g.oben + r
                expected[(px, py)] = blend(expected.get((px, py), bg), fg, d)

    char = 0
    ink_count = 0
    wrong = 0
    empty = []
    bad_cells = []
    for (c, gx, gy) in places:
        g = face.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        char += 1
        set_count = 0
        bad_count = 0
        ink = 0
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) == 0:
                    continue
                px = gx + g.links + k
                py = gy - g.oben + r
                if ymax is not None and py >= ymax:
                    continue
                set_count += 1
                actual = image.pixel(px, py)
                if actual is None:
                    bad_count += 1
                    continue
                if actual != bg:
                    ink += 1
                w = expected[(px, py)]
                if max(abs(actual[j] - w[j]) for j in range(3)) > tol:
                    bad_count += 1
        ink_count += set_count
        wrong += bad_count
        if set_count > 0 and ink == 0:
            empty.append(visible(c))
        if bad_count and len(bad_cells) < 8:
            bad_cells.append("'%s' at x=%d: %d of %d ink pixels wrong"
                            % (visible(c), gx, bad_count, set_count))
    print("%d chars, %d ink pixels checked, %d wrong"
          % (char, ink_count, wrong), end="")
    if empty:
        print(" -- EMPTY: %s" % " ".join(empty))
        return 1
    if wrong:
        print()
        for z in bad_cells:
            print("    " + z)
        return 1
    print("")
    return 0


def cmd_tright(a):
    raster = _load_raster()
    face = raster.Schrift(a[1], int(a[2]))
    text = a[11]
    width = face.laufweite(text) >> 6
    last = None
    import io
    import contextlib
    for off in (0, -1, 1, -2, 2):
        b = list(a)
        b[3] = str(int(a[3]) - width + off)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = cmd_tchain(b)
        last = (rc, buf.getvalue())
        if rc == 0:
            print(last[1], end="")
            return 0
    print(last[1], end="")
    return last[0]


def cmd_ttext(a):
    raster = _load_raster()
    image = Image(a[0])
    face = raster.Schrift(a[1], int(a[2]))
    x, y = int(a[3]), int(a[4])
    fg = (int(a[5]), int(a[6]), int(a[7]))
    bg = (int(a[8]), int(a[9]), int(a[10]))
    text = a[11]
    tol = int(a[12]) if len(a) > 12 else 0
    places = [(c, x + (dx >> 6), y) for (c, dx) in face.stellen(text)]
    n, ink_count, wrong, empty, bad_cells = _check_glyphs(
        image, face, places, y, fg, bg, tol)
    print("%d chars, %d ink pixels checked, %d wrong"
          % (n, ink_count, wrong), end="")
    if empty:
        print(" -- EMPTY: %s" % " ".join(empty))
        return 1
    if wrong:
        print()
        for z in bad_cells:
            print("    " + z)
        return 1
    print("")
    return 0


def cmd_tink(a):
    raster = _load_raster()
    image = Image(a[0])
    face = raster.Schrift(a[1], int(a[2]))
    x, y = int(a[3]), int(a[4])
    fg = (int(a[5]), int(a[6]), int(a[7]))
    bg = (int(a[8]), int(a[9]), int(a[10]))
    if bg[0] < 0:
        bg = image.pixel(x - 2, y - 5)
    text = a[11]
    min_share = int(a[12]) / 100.0 if len(a) > 12 else 0.70
    char = 0
    weak = []
    drift = 0
    explained = set()
    x0 = x1 = y0 = y1 = None
    for (c, dx) in face.stellen(text):
        g = face.glyphe(c)
        if g.w == 0 or g.h == 0:
            continue
        points = []
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) >= 160:
                    points.append((k, r))
        if not points:
            continue
        char += 1
        best_share = 0.0
        best_dx = drift
        best_dy = 0
        for ddy in (0, -1, 1):
            for ddx in range(drift - 2, drift + 3):
                gx = x + (dx >> 6) + ddx
                gy = y + ddy
                hits = 0
                for (k, r) in points:
                    actual = image.pixel(gx + g.links + k, gy - g.oben + r)
                    if actual is None:
                        continue
                    if sum(abs(actual[j] - bg[j]) for j in range(3)) >= 90:
                        hits += 1
                share = hits / len(points)
                if share > best_share:
                    best_share = share
                    best_dx = ddx
                    best_dy = ddy
        if best_share >= min_share:
            drift = best_dx
        if best_share < min_share:
            weak.append("'%s' %d%%" % (visible(c), int(best_share * 100)))
        gx = x + (dx >> 6) + best_dx
        gy = y + best_dy
        for r in range(g.h):
            for k in range(g.w):
                if g.punkt(k, r) >= 40:
                    explained.add((gx + g.links + k, gy - g.oben + r))
        left = gx + g.links
        if x0 is None or left < x0:
            x0 = left
        if x1 is None or left + g.w > x1:
            x1 = left + g.w
        top = gy - g.oben
        if y0 is None or top < y0:
            y0 = top
        if y1 is None or top + g.h > y1:
            y1 = top + g.h
    print("%d chars, %d without ink (tolerant)" % (char, len(weak)),
          end="")
    foreign = 0
    total = 0
    if x0 is not None:
        for py in range(y0 - 1, y1 + 1):
            for px in range(x0 - 1, x1 + 2):
                actual = image.pixel(px, py)
                if actual is None:
                    continue
                if sum(abs(actual[j] - bg[j]) for j in range(3)) < 90:
                    continue
                total += 1
                if not any((px + i, py + j) in explained
                           for i in (-1, 0, 1) for j in (-1, 0, 1)):
                    foreign += 1
    if total:
        print(", %d of %d ink pixels without glyph" % (foreign, total), end="")
    if weak:
        print(" -- " + " ".join(weak))
        return 1
    if total and foreign * 4 > total:
        print(" -- too much foreign ink")
        return 1
    print("")
    return 0


def cmd_tgrid(a):
    raster = _load_raster()
    image = Image(a[0])
    face = raster.Schrift(a[1], int(a[2]))
    x0, y0 = int(a[3]), int(a[4])
    cell_w, cell_h = int(a[5]), int(a[6])
    row, column = int(a[7]), int(a[8])
    fg = (int(a[9]), int(a[10]), int(a[11]))
    bg = (int(a[12]), int(a[13]), int(a[14]))
    text = a[15]
    tol = int(a[16]) if len(a) > 16 else 0
    baseline = y0 + row * cell_h + face.aufsteiger()
    places = [(ord(ch), x0 + (column + i) * cell_w, baseline)
               for i, ch in enumerate(text)]
    n, ink_count, wrong, empty, bad_cells = _check_glyphs(
        image, face, places, baseline, fg, bg, tol, cell_w)
    print("row %d from column %d: %d chars, %d ink pixels, %d wrong"
          % (row, column, n, ink_count, wrong), end="")
    if empty:
        print(" -- EMPTY: %s" % " ".join(empty))
        return 1
    if wrong:
        print()
        for z in bad_cells:
            print("    " + z)
        return 1
    print("")
    return 0


def cmd_smooth(a):
    image = Image(a[0])
    x, y, w, h = int(a[1]), int(a[2]), int(a[3]), int(a[4])
    fg = (int(a[5]), int(a[6]), int(a[7]))
    bg = (int(a[8]), int(a[9]), int(a[10]))
    minimum = int(a[11]) if len(a) > 11 else 1
    between = 0
    total = 0
    for py in range(y, y + h):
        for px in range(x, x + w):
            p = image.pixel(px, py)
            if p is None:
                continue
            total += 1
            if p != fg and p != bg:
                between += 1
    print("%d of %d pixels are intermediate levels (minimum %d)"
          % (between, total, minimum))
    return 0 if between >= minimum else 1


def cmd_rect(a):
    image = Image(a[0])
    x, y, w, h = int(a[1]), int(a[2]), int(a[3]), int(a[4])
    color = (int(a[5]), int(a[6]), int(a[7]))
    wrong = 0
    total = 0
    for px in range(x, x + w):
        for py in (y, y + h - 1):
            total += 1
            if image.pixel(px, py) != color:
                wrong += 1
    for py in range(y, y + h):
        for px in (x, x + w - 1):
            total += 1
            if image.pixel(px, py) != color:
                wrong += 1
    outside = 0
    for px in range(x - 1, x + w + 1):
        for py in (y - 1, y + h):
            if image.pixel(px, py) == color:
                outside += 1
    print("frame %dx%d at (%d,%d): %d of %d edge pixels wrong, "
          "%d hits one row outside" % (w, h, x, y, wrong, total, outside))
    return 0 if wrong == 0 and outside == 0 else 1


COMMANDS = {
    "size": cmd_size,
    "pixel": cmd_pixel,
    "area": cmd_area,
    "nonblank": cmd_nonblank,
    "text": cmd_text,
    "console": cmd_console,
    "find": cmd_find,
    "font": cmd_font,
    "read": cmd_read,
    "ttext": cmd_ttext,
    "tchain": cmd_tchain,
    "tright": cmd_tright,
    "tink": cmd_tink,
    "tgrid": cmd_tgrid,
    "smooth": cmd_smooth,
    "rect": cmd_rect,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("usage: checkshot.py <" + "|".join(COMMANDS) + "> <args>")
        return 2
    try:
        return COMMANDS[sys.argv[1]](sys.argv[2:])
    except Exception as e:
        print("ERROR: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
