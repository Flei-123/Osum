#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/shotcheck.py -- MEASURE A SCREENSHOT, DO NOT LOOK AT IT.

Twice in this repository a picture with a real defect in it was passed
by a test that only asked whether a picture had been produced. Round
LOOK's list of complaints was "no umlauts", "no symbols", "it looks like
Windows XP" -- three things a person saw in a screenshot and no runner
had. So this asks a picture the three questions a person asks, in
numbers:

    shotcheck.py <shot.ppm|png> <serial.txt> --window=x,y,w,h [--win=N]

  1. EMPTY LABEL. Every `wlib: text ... x= base= tw= t=` line names a
     place where letters were drawn and how wide they are. If that box
     holds no pixel differing from the reported background, nothing was
     drawn there. Invisible to any test that counts colours in a whole
     picture.

  2. CUT OFF. The ink has to lie inside the window it was drawn in, and
     it has to stop before the right edge of its own reported width: ink
     in the last column is ink that continues past it.

  3. OVERLAPPING. Two reported texts must not have ink in the same
     pixel.

THREE THINGS THAT HAD TO BE GOT RIGHT BEFORE THE NUMBERS MEANT ANYTHING,
and every one of them produced a false failure first:

  * ONE WINDOW. The desktop has five processes painting; the launcher's
    list rows sit under the settings window and overlap everything.
    Text from another window is not a defect, it is a window behind
    this one. So this measures ONE window, chosen as the one with the
    most text in the region of the log that matters.

  * THE STATE AT THE TIME OF THE PHOTO, not the last state ever
    reported. Round LOOK wrote that rule down after paying for it. The
    settings program prints a full block of `settings: rect name=w..`
    every time it changes page, so everything after the LAST such block
    is the page that is on the screen.

  * THE WIDTH COMES FROM THE PROGRAM. Guessing it from the letter count
    produced 86 false overlaps in one picture: the box drawn around a
    label reached into the widget next door and found its pixels.

WHAT IT DOES NOT DO, said plainly: it does not re-rasterise the glyphs.
`tools/look/umlaut.py` does that, against `tools/ttf/raster.py`, and it
is the stronger check of the two. This is the cheap one that runs over
every text on the screen instead of over a chosen few.
"""
import re
import sys


# ------------------------------------------------------------------ picture
def read_ppm(path):
    d = open(path, "rb").read()
    if not d.startswith(b"P6"):
        raise SystemExit("not a P6 PPM: %s" % path)
    f = []
    at = 2
    while len(f) < 3:
        while at < len(d) and d[at:at + 1].isspace():
            at += 1
        if d[at:at + 1] == b"#":
            while d[at:at + 1] not in (b"\n", b""):
                at += 1
            continue
        a = at
        while at < len(d) and not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[a:at]))
    at += 1
    return f[0], f[1], d[at:]


def read_any(path):
    if path.endswith(".ppm"):
        return read_ppm(path)
    from PIL import Image
    im = Image.open(path).convert("RGB")
    return im.size[0], im.size[1], im.tobytes()


class Pic(object):
    def __init__(self, path):
        self.w, self.h, self.d = read_any(path)

    def at(self, x, y):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return None
        o = (y * self.w + x) * 3
        return (self.d[o], self.d[o + 1], self.d[o + 2])


# ------------------------------------------------------------------ the log
TEXT = re.compile(
    r"wlib: text win=(\d+) kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    # RUNDE MERGE-2: FELDWEISE, NICHT IN EINER FESTEN REIHENFOLGE.
    # Runde SOFTUI haengt hinter `tw=` noch `ax=`/`ay=` an; mit dem
    # alten Muster passte danach KEINE einzige Zeile mehr, und dieses
    # Werkzeug meldete "texts 0 measured 0" -- also 0 statt >= 12
    # gemessener Beschriftungen, ohne dass am Bild irgendetwas fehlte.
    # Dieselbe Stelle hat STATUS-SOFTUI.md fuer tools/look/run.sh und
    # tools/look/umlaut.py berichtigt und diese hier uebersehen.
    r" tw=(\d+)(?: [a-z]+=-?\d+)* t=(.*)")

# RUNDE THEMESTORE: WO DAS FENSTER STEHT, gesagt von dem Fenster.
# Bis hierher nahm dieses Werkzeug fuer jedes Fenster ausser dem der
# Einstellungen 0,0 an -- und mass damit Stellen des Schreibtischs
# statt Beschriftungen. `cx`/`cy` ist der Ursprung der MALFLAECHE, in
# denselben Koordinaten wie die Aufnahme.
WINRE = re.compile(
    r"wlib: win id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) cx=(\d+) cy=(\d+)")

# ... und wie hoch eine Zeile ist. Geraten wurde 16 hinauf und 6
# hinunter; die Bibliothek sagt es jetzt selbst.
FONTRE = re.compile(r"wlib: font ui px=(\d+) asc=(\d+) h=(\d+)")


def parse(path):
    body = open(path, "rb").read().decode("latin1")
    # everything after the LAST full rectangle report is the page that
    # is on the screen now
    cut = body.rfind("settings: rect name=waa ")
    tail = body[cut:] if cut >= 0 else body
    out = []
    for raw in tail.splitlines():
        m = TEXT.search(raw)
        if not m:
            continue
        out.append(dict(win=int(m.group(1)), kind=int(m.group(2)),
                        x=int(m.group(3)), base=int(m.group(4)),
                        fg=int(m.group(5)), bg=int(m.group(6)),
                        tw=int(m.group(7)), t=m.group(8)))
    # Die Fensterzeilen stehen am ANFANG des Laufs (ein Fenster wird
    # einmal angelegt), also aus dem ganzen Text und nicht aus dem
    # Schwanz. Die letzte Meldung je Fenster gilt.
    wins = {}
    for m in WINRE.finditer(body):
        wins[int(m.group(1))] = dict(x=int(m.group(2)), y=int(m.group(3)),
                                     w=int(m.group(4)), h=int(m.group(5)),
                                     cx=int(m.group(6)), cy=int(m.group(7)))
    font = None
    for m in FONTRE.finditer(body):
        font = (int(m.group(2)), int(m.group(3)) - int(m.group(2)))
    return out, wins, font


def rgb(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


def near(a, b, tol):
    return max(abs(a[i] - b[i]) for i in range(3)) <= tol


def inkbox(pic, x0, y0, x1, y1, bg, tol):
    """Der Kasten um die Tinte UND die Punkte selbst.

    RUNDE THEMESTORE: die Punkte sind neu, und sie sind der Grund, dass
    diese Datei ueberhaupt noch einmal angefasst wurde. `ueberlappend`
    hiess bis hierher "zwei KAESTEN schneiden sich" -- und zwei
    untereinander stehende Zeilen einer Liste tun das immer: der Kasten
    ist so hoch wie die Schrift werden kann (Oberlaenge plus
    Unterlaenge), die Zeilen stehen zwanzig Bildpunkte auseinander, und
    schon melden drei Zeilen, die einander nicht beruehren, zwei
    Ueberlappungen. Der Text der Datei sagt seit dem ersten Tag
    "must not have ink in the same pixel"; jetzt wird das auch gemessen.
    """
    lo_x = lo_y = hi_x = hi_y = None
    pts = set()
    for y in range(max(y0, 0), min(y1, pic.h)):
        for x in range(max(x0, 0), min(x1, pic.w)):
            p = pic.at(x, y)
            if p is None or near(p, bg, tol):
                continue
            pts.add((x, y))
            lo_x = x if lo_x is None or x < lo_x else lo_x
            hi_x = x if hi_x is None or x > hi_x else hi_x
            lo_y = y if lo_y is None or y < lo_y else lo_y
            hi_y = y if hi_y is None or y > hi_y else hi_y
    if not pts:
        return None
    return (lo_x, lo_y, hi_x, hi_y, len(pts), pts)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    pic = Pic(argv[1])
    texts, wins, font = parse(argv[2])
    ox = oy = 0
    forced = False
    ww, wh = pic.w, pic.h
    want_win = None
    for a in argv[3:]:
        if a.startswith("--window="):
            ox, oy, ww, wh = (int(v) for v in a.split("=", 1)[1].split(","))
            forced = True
        elif a.startswith("--win="):
            want_win = int(a.split("=", 1)[1])
    if want_win is None and texts:
        count = {}
        for t in texts:
            count[t["win"]] = count.get(t["win"], 0) + 1
        want_win = max(count, key=lambda k: count[k])
    texts = [t for t in texts if t["win"] == want_win and t["t"].strip()]
    # the last report of each label is where it is now
    last = {}
    for t in texts:
        last[(t["kind"], t["t"])] = t
    texts = list(last.values())

    # DER URSPRUNG KOMMT AUS DER FENSTERZEILE, wenn es eine gibt --
    # `--window=` bleibt der Vorrang fuer den, der es besser weiss.
    if not forced and want_win in wins:
        w = wins[want_win]
        ox, oy, ww, wh = w["cx"], w["cy"], w["w"], w["h"]
    # Die gemessenen Zahlen der Schrift, nicht die geratenen.
    asc, desc = font if font else (16, 6)
    bad = []
    boxes = []
    empty = 0
    for t in texts:
        x = ox + t["x"]
        y0 = oy + t["base"] - asc
        y1 = oy + t["base"] + desc
        x1 = x + t["tw"]
        # AUF DIE MALFLAECHE BESCHNITTEN. Ein Text, dessen gemeldete
        # Breite ueber den Fensterrand hinausreicht, holte sonst die
        # Farbe des RAHMENS als "Tinte" herein -- und der Rahmen ist
        # nicht sein Text. Dass er zu breit ist, sagt der Vergleich
        # weiter unten, und zwar als das, was es ist.
        box = inkbox(pic, x, y0, min(x1, ox + ww), y1, rgb(t["bg"]), 10)
        if box is None:
            empty += 1
            bad.append("EMPTY  '%s' at %d,%d w=%d (bg %06x): no pixel differs"
                       % (t["t"][:32], x, oy + t["base"], t["tw"], t["bg"]))
            continue
        boxes.append((t["t"], box, x, x1))
    cut = 0
    for name, b, x, x1 in boxes:
        if x < ox or b[1] < oy or x1 > ox + ww or b[3] >= oy + wh:
            cut += 1
            bad.append("CUT    '%s' at %d..%d (ink %s) leaves the window "
                       "%d,%d %dx%d"
                       % (name[:32], x, x1, b[:4], ox, oy, ww, wh))
    over = 0
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = boxes[i][1], boxes[j][1]
            # erst der billige Kasten, dann die teure Wahrheit: nur
            # gemeinsame PUNKTE sind eine Ueberlappung.
            if a[0] > b[2] or b[0] > a[2] or a[1] > b[3] or b[1] > a[3]:
                continue
            if not (a[5] & b[5]):
                continue
            over += 1
            if over <= 12:
                bad.append("OVER   '%s' %s and '%s' %s"
                           % (boxes[i][0][:24], a[:4],
                              boxes[j][0][:24], b[:4]))
    print("shotcheck: win %s  texts %d  measured %d  empty %d  cut %d  "
          "overlapping %d" % (want_win, len(texts), len(boxes), empty, cut,
                              over))
    for line in bad[:30]:
        print("  " + line)
    return 0 if (empty == 0 and cut == 0 and over == 0) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
