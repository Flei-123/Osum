#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import subprocess
import sys

BORDER = 2
TITLE = int(os.environ.get("UMLAUT_TITLE", "22"))

WIN = re.compile(
    rb"wm: win nr=\d+ id=\d+ z=\d+ layer=\d+ hidden=(\d+) deco=(\d+) "
    rb"x=(\d+) y=(\d+) w=(\d+) h=(\d+).*?t=\[([^\]]*)\]")

WINZ = re.compile(
    rb"wm: win nr=\d+ id=\d+ z=(\d+) layer=(\d+) hidden=(\d+) deco=(\d+) "
    rb"x=(\d+) y=(\d+) w=(\d+) h=(\d+).*?t=\[([^\]]*)\]")


def frei_bis(roh, title, y0, y1, x0):
    own = None
    window_2 = []
    for m in WINZ.finditer(roh):
        e = dict(z=int(m.group(1)), hidden=m.group(3) != b"0",
                 deco=m.group(4) == b"1", x=int(m.group(5)),
                 y=int(m.group(6)), w=int(m.group(7)), h=int(m.group(8)),
                 t=m.group(9).decode("utf-8", "replace"))
        window_2.append(e)
        if e["t"] == title and not e["hidden"]:
            own = e
    if own is None:
        return None
    limit = None
    for e in window_2:
        if e["hidden"] or e["z"] <= own["z"] or e is own:
            continue
        ex0 = e["x"] - (BORDER if e["deco"] else 0)
        ey0 = e["y"] - (TITLE if e["deco"] else 0)
        ex1 = e["x"] + e["w"] + (BORDER if e["deco"] else 0)
        ey1 = e["y"] + e["h"] + (BORDER if e["deco"] else 0)
        if ey1 <= y0 or ey0 >= y1:
            continue
        if ex1 <= x0:
            continue
        if limit is None or ex0 < limit:
            limit = ex0
    return limit


def window_2(roh, title):
    treffer = None
    for m in WIN.finditer(roh):
        if m.group(7).decode("utf-8", "replace") == title:
            treffer = m
    if treffer is None:
        return None
    if treffer.group(1) != b"0":
        return None
    return (int(treffer.group(3)), int(treffer.group(4)),
            int(treffer.group(5)), int(treffer.group(6)),
            treffer.group(2) == b"1")


def bis_zum_photo(roh):
    i = roh.find(b"wm: hold")
    return roh if i < 0 else roh[:i]


def gemalt(roh, text):
    roh = bis_zum_photo(roh)
    pat = (rb"kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)(?: [a-z]+=\d+)* t="
           + re.escape(text.encode("utf-8")))
    treffer = list(re.finditer(pat, roh))
    if not treffer:
        return None
    m = treffer[-1]
    px = re.search(rb" px=(\d+) t=", m.group(0))
    return tuple(int(m.group(i)) for i in range(1, 6)) + (
        int(px.group(1)) if px else 15,)


def rgb(v):
    return [str((v >> 16) & 255), str((v >> 8) & 255), str(v & 255)]


GITTER = re.compile(
    rb"wm: termgitter win=(\d+) x=(\d+) y=(\d+) cellw=(\d+) cellh=(\d+)"
    rb" asc=(\d+) px=(\d+)")


def gitter(roh):
    treffer = None
    for m in GITTER.finditer(roh):
        treffer = m
    if treffer is None:
        return None
    return tuple(int(treffer.group(i)) for i in range(2, 8))


def grundfarben(ppm, x0, y0, x1, y1):
    b = open(ppm, "rb").read()
    if not b.startswith(b"P6"):
        return None
    felder = []
    at = 2
    while len(felder) < 3:
        while at < len(b) and b[at:at + 1].isspace():
            at += 1
        if b[at:at + 1] == b"#":
            while b[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        a = at
        while at < len(b) and not b[at:at + 1].isspace():
            at += 1
        felder.append(int(b[a:at]))
    at += 1
    w, h = felder[0], felder[1]
    zaehl = {}
    for y in range(max(y0, 0), min(y1, h)):
        for x in range(max(x0, 0), min(x1, w)):
            o = at + (y * w + x) * 3
            p = (b[o], b[o + 1], b[o + 2])
            zaehl[p] = zaehl.get(p, 0) + 1
    if not zaehl:
        return None
    hg = max(zaehl, key=lambda k: zaehl[k])
    vg = max(zaehl, key=lambda k: sum(abs(k[i] - hg[i]) for i in range(3)))
    return vg, hg


def term_check(serial, ppm, text, line_3, column, tol, char):
    roh = open(serial, "rb").read()
    g = gitter(roh)
    if g is None:
        print("umlaut: [%s] no `wm: termgitter` line in the capture"
              % char)
        return 1
    x0, y0, cw, chh, asc, px = g
    ax = x0 + column * cw
    ay = y0 + line_3 * chh + asc
    farben = grundfarben(ppm, ax, ay - asc, ax + len(text) * cw, ay + 4)
    if farben is None:
        print("umlaut: [%s] line %d cannot be found in the image"
              % (char, line_3))
        return 1
    vg, hg = farben
    r = subprocess.run(
        ["python3", "tools/gfx/checkshot.py", "tgrid", ppm,
         "assets/osum-mono.ttf", str(px), str(x0), str(y0),
         str(cw), str(chh), str(line_3), str(column)]
        + [str(v) for v in vg] + [str(v) for v in hg] + [text, tol],
        capture_output=True, text=True)
    header = r.stdout.strip().split("\n")[0] if r.stdout else r.stderr.strip()
    print("umlaut: [%s] termgitter zeile=%d spalte=%d x=%d y=%d "
          "fg=%02x%02x%02x bg=%02x%02x%02x tol=%s -- %s"
          % (char, line_3, column, ax, ay, vg[0], vg[1], vg[2],
             hg[0], hg[1], hg[2], tol, header))
    for z in r.stdout.strip().split("\n")[1:]:
        print("        " + z)
    return r.returncode


def main(argv):
    if len(argv) < 4:
        print("umlaut: <serial> <ppm> <fenstertitel> <text> [toleranz]")
        print("        <serial> <ppm> --gitter=<zeile>,<spalte> <text> "
              "[toleranz]")
        return 2
    kette = "--kette" in argv
    argv = [x for x in argv if x != "--kette"]
    ink = "--ink" in argv
    argv = [x for x in argv if x != "--ink"]
    if argv[2].startswith("--gitter="):
        text = argv[3]
        char = "".join(sorted(set(c for c in text if c in "äöüÄÖÜß")))
        if not char:
            print("umlaut: %r traegt gar keinen Umlaut" % text)
            return 2
        line_3, column = (int(v) for v in argv[2].split("=", 1)[1].split(","))
        return term_check(argv[0], argv[1], text, line_3, column,
                            argv[4] if len(argv) > 4 else "0", char)
    serial, ppm, title, text = argv[0], argv[1], argv[2], argv[3]
    tol = argv[4] if len(argv) > 4 else "0"
    char = "".join(sorted(set(c for c in text if c in "äöüÄÖÜß")))
    if not char:
        print("umlaut: %r traegt gar keinen Umlaut" % text)
        return 2
    roh = open(serial, "rb").read()

    w = window_2(roh, title)
    if w is None:
        print("umlaut: [%s] no visible window '%s'" % (char, title))
        return 1
    wx, wy, ww, wh, deco = w
    t = gemalt(roh, text)
    if t is None:
        print("umlaut: [%s] '%s' wurde nicht gemalt" % (char, text[:40]))
        return 1
    kind, tx, tb, fg, bg, px = t

    ix = wx + (BORDER if deco else 0)
    iy = wy + (TITLE if deco else 0)
    if title == "Datei-Explorer":
        sm = re.findall(rb"explorer: strip h=(\d+)", roh)
        if sm and deco:
            iy -= int(sm[-1])
    ax, ay = ix + tx, iy + tb

    sys.path.insert(0, os.path.join("tools", "ttf"))
    import raster
    font = raster.Font_2("assets/osum-sans.ttf", px)
    stellen = list(font.stellen(text))
    width_2 = ((stellen[-1][1] >> 6) if stellen else 0) + 12
    if tx + width_2 > ww:
        print("umlaut: [%s] '%s' laeuft von x=%d bis %d aus einem Fenster "
              "heraus, das %d breit ist -- nicht messbar"
              % (char, text[:30], tx, tx + width_2, ww))
        return 1

    up = 20
    limit = frei_bis(roh, title, ay - up, ay + 6, ax)
    if limit is not None:
        sicht = text
        for k, (c, x26) in enumerate(stellen):
            if ax + (x26 >> 6) + 12 > limit:
                sicht = text[:k]
                break
        if not sicht.strip() or not any(c in "äöüÄÖÜß" for c in sicht):
            print("umlaut: [%s] '%s' ist ab x=%d verdeckt -- vom Umlaut "
                  "ist nichts zu sehen" % (char, text[:30], limit))
            return 1
        if sicht != text:
            print("        verdeckt ab x=%d -- gemessen wird '%s'"
                  % (limit, sicht))
        text = sicht

    r = subprocess.run(
        ["python3", "tools/gfx/checkshot.py",
         "tink" if ink else ("tchain" if kette else "ttext"), ppm,
         "fui:assets/osum-sans.ttf", str(px), str(ax), str(ay)]
        + rgb(fg) + rgb(bg) + [text, tol],
        capture_output=True, text=True)
    header = r.stdout.strip().split("\n")[0] if r.stdout else r.stderr.strip()
    print("umlaut: [%s] kind=%d %s x=%d y=%d tol=%s -- %s"
          % (char, kind, title, ax, ay, tol, header))
    for z in r.stdout.strip().split("\n")[1:]:
        print("        " + z)
    return r.returncode


if __name__ == "__main__":
    os.chdir(os.environ.get("OSUM_ROOT", "."))
    sys.exit(main(sys.argv[1:]))
