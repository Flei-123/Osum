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
                 [--leiste] [--linien] [--knoepfe]

`--knoepfe` fragt jeden gemeldeten Knopf (`wlib: knopf ...`), ob er im
Bild ueberhaupt einen Umriss hat -- eine Flaeche in Weiss auf einer
Karte in fast Weiss ist von einer Beschriftung nicht zu unterscheiden,
und genau so sah der Knopf "Uebernehmen" der Seite Darstellung aus. Die
Zahlen `knopf` und `ohnekante` stehen immer in der Ausgabezeile; in den
Rueckgabewert gehen sie nur mit diesem Schalter ein.

Seit RUNDE GLAS (fix-r4-1) fragt derselbe Schalter eine zweite Sache:
liegt die BESCHRIFTUNG eines Knopfes innerhalb seines Umrisses? Der
Knopf "Mit Konto verknuepfen" der Seite Vorlagen hatte einen Rahmen von
150 Bildpunkten und ein Wort von 156 -- sein Rand lief also mitten
durch die Schrift, und angeschaut war das eine Beschriftung mit einem
Strich darueber. Die Zahl heisst `ueberstand`.

`--leiste` stellt dieselben drei Fragen zusaetzlich an die Taskleiste
(RUNDE GLAS, Nachtrag -- bis dahin hat dieses Werkzeug GENAU EIN
Fenster gemessen und die Leiste nie). Sie kommt auf eine eigene
Ausgabezeile `shotcheck: leiste ...` und geht in den Rueckgabewert ein.

`--linien` stellt eine Frage, die aus gemeldeten Rechtecken nicht zu
beantworten ist: laeuft eine RAHMENLINIE durch die Schrift? Zwei
Rechtecke, die sich nur BERUEHREN, melden keine Ueberlappung -- die
Statuszeile "bereit" der Einstellungen sass trotzdem genau auf der
unteren Kante der linken Karte. Gesucht wird links UND rechts neben
der Tinte, auf derselben Bildzeile, ein einfarbiger Lauf von zehn
Bildpunkten, der nicht der gemessene Grund ist. Die Zahl `linie` steht
immer in der Ausgabezeile; in den Rueckgabewert geht sie nur mit
diesem Schalter ein.

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

  4. CUT SHORT. Every line says how many octets OF THE LABEL are on
     the screen (`nq=`) and how many the label really has (`nv=`); the
     three dots of an elision are not part of the label and do not
     count. Fewer on the screen than meant is a shortening: it counts
     as `gekuerzt`, and if it happened WITHOUT the three dots that tell
     a reader something is missing, it is a silent cut and counts as
     `cut`.

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


TEXT = re.compile(
    r"wlib: text win=(\d+) kind=(\d+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    r" tw=(\d+)(?: [a-z]+=-?\d+)* t=(.*)")

WINRE = re.compile(
    r"wlib: win id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+) cx=(\d+) cy=(\d+)")

FONTRE = re.compile(r"wlib: font ui px=(\d+) asc=(\d+) h=(\d+)")

KURZ = re.compile(r" nq=(\d+) nv=(\d+)")

BARTEXT = re.compile(
    r"taskbar: text (\w+) x=(\d+) base=(\d+) fg=(\d+) bg=(\d+)"
    r" tw=(\d+) t=(.*)")
BARWIN = re.compile(
    r"taskbar: STEHT x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
BARRECT = re.compile(
    r"taskbar: (?:(start)|btn i=\d+ id=\d+|field (\w+)|pin \S+) "
    r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)")

BUTTON = re.compile(
    r"wlib: knopf x=(\d+) y=(\d+) w=(\d+) h=(\d+) r=(\d+) ax=(\d+) ay=(\d+)")


def kanten(pic, x, y, w, h, r, tol=8, stufe=12, anteil=60):
    """Wie viele der vier Kanten eines Knopfes im Bild wirklich da sind.

    Drei Bildpunkte je Stelle: AUF der Kante, zwei davor (draussen) und
    drei dahinter (die Flaeche). Als Kante zaehlt
      * eine LINIE -- der Punkt auf der Kante unterscheidet sich von
        beiden Nachbarn (so malt `fuib.ring` sie, gemessen: Linie
        227,233,240 zwischen zweimal 246,247,247), oder
      * eine STUFE -- Flaeche und Umgebung sind verschieden genug, dass
        der Knopf auch ohne Linie als Flaeche zu sehen ist.
    Die zweite Bedingung ist absichtlich strenger (12 statt 8 Stufen):
    genau der Fall, der diese Probe ausgeloest hat, war eine Flaeche in
    Weiss auf einer Karte in #f8fafc -- neun Stufen, und niemand sieht
    das.
    """
    gefunden = 0
    seiten = (
        [((x + i, y), (x + i, y - 2), (x + i, y + 3))
         for i in range(r + 2, w - r - 2)],
        [((x + i, y + h - 1), (x + i, y + h + 1), (x + i, y + h - 4))
         for i in range(r + 2, w - r - 2)],
        [((x, y + j), (x - 2, y + j), (x + 3, y + j))
         for j in range(r + 2, h - r - 2)],
        [((x + w - 1, y + j), (x + w + 1, y + j), (x + w - 4, y + j))
         for j in range(r + 2, h - r - 2)],
    )
    for page in seiten:
        n = 0
        d = 0
        for auf, aussen, innen in page:
            a, b, c = pic.at(*auf), pic.at(*aussen), pic.at(*innen)
            if a is None or b is None or c is None:
                continue
            n += 1
            line_2 = (max(abs(a[i] - b[i]) for i in range(3)) >= tol
                     and max(abs(a[i] - c[i]) for i in range(3)) >= tol)
            if line_2 or max(abs(c[i] - b[i]) for i in range(3)) >= stufe:
                d += 1
        if n > 0 and d * 100 >= n * anteil:
            gefunden += 1
    return gefunden


def knoepfe_messen(pic, tail, ox, oy, ww, wh, bar, texts=()):
    """(gemessen, ohne Kante, mit Ueberstand, Befunde) je Knopf.

    Gemessen wird nur, was im GEMESSENEN FENSTER liegt und auf dem
    Schirm zu sehen ist: ein Knopf eines Fensters dahinter waere
    verdeckt, und ein Knopf unter der Leiste ist es auch -- beides ist
    kein fehlender Rand.

    ============================= RUNDE GLAS (fix-r4-1): DER UEBERSTAND

    Die Kantenprobe darueber beantwortet die Frage "hat das Ding einen
    Umriss?". Sie beantwortet NICHT die Frage, die der Knopf "Mit Konto
    verknuepfen" auf Bild 09 gestellt hat: sein Umriss war da (eine
    sehr helle Linie von x=38 bis x=189), nur war seine Beschriftung
    156 Bildpunkte breit und stand von x=40 bis x=196 -- sieben
    Bildpunkte davon LAGEN AUF UND NEBEN DEM RAHMEN. Angeschaut ist das
    ein Wort mit einem Strich darueber und kein Knopf, und kein
    Pruefer dieses Baums hat es gesehen: die Schriftpruefung misst
    gegen das FENSTER, und im Fenster lag der Text ja.

    Also wird ab jetzt jede gemeldete Beschriftung, deren Grundlinie in
    einem gemeldeten Knopf liegt, gegen die Kanten DIESES Knopfes
    gehalten. Ein Bildpunkt Luft auf jeder Seite ist erlaubt (die
    Kantenglaettung eines Buchstabens reicht so weit); alles darueber
    ist ein Ueberstand und wird gezaehlt.
    """
    letzte = {}
    for m in BUTTON.finditer(tail):
        v = tuple(int(g) for g in m.groups())
        letzte[(v[5], v[6])] = v
    bad = []
    gemessen = 0
    without = 0
    over_2 = 0
    for (x, y, w, h, r, ax, ay) in letzte.values():
        if w < 8 or h < 8:
            continue
        if ax < ox or ay < oy or ax + w > ox + ww or ay + h > oy + wh:
            continue
        if ax < 1 or ay < 1 or ax + w + 1 > pic.w or ay + h + 1 > pic.h:
            continue
        if (bar is not None and ay + h > bar["y"]
                and ax < bar["x"] + bar["w"] and ax + w > bar["x"]):
            continue
        gemessen += 1
        k = kanten(pic, ax, ay, w, h, r)
        if k == 0:
            without += 1
            bad.append("BUTTON at %d,%d %dx%d r=%d has not a single "
                       "Umrisskante -- er sieht aus wie eine Beschriftung"
                       % (ax, ay, w, h, r))
        for t in texts:
            if not t["t"].strip() or t["tw"] <= 0:
                continue
            tx = ox + t["x"]
            tb = oy + t["base"]
            if tb < ay or tb > ay + h:
                continue
            if tx < ax - 2 or tx > ax + w:
                continue
            if tx >= ax + 1 and tx + t["tw"] <= ax + w - 1:
                continue
            over_2 += 1
            bad.append("BUTTON at %d,%d %dx%d: the label '%s' "
                       "steht von %d bis %d und ragt ueber den Umriss "
                       "(%d bis %d) hinaus"
                       % (ax, ay, w, h, t["t"][:24], tx, tx + t["tw"],
                          ax, ax + w))
    return gemessen, without, over_2, bad


def parse_bar(path):
    """Die Beschriftungen der Leiste und das Rechteck, in dem sie stehen.

    Der LETZTE Bericht je Marke gilt, genau wie beim Fenster: die
    Leiste malt bei jedem Uhrenwechsel neu, und was vor zehn Sekunden
    einmal dort stand, ist auf der Aufnahme nicht mehr zu finden.
    """
    body = open(path, "rb").read().decode("latin1")
    bar = None
    for m in BARWIN.finditer(body):
        bar = dict(x=int(m.group(1)), y=int(m.group(2)),
                   w=int(m.group(3)), h=int(m.group(4)))
    stellen = [m.start() for m in
               re.finditer(r"taskbar: text start ", body)]
    if len(stellen) > 1:
        body = body[stellen[-2] + 1:]
    last = {}
    for m in BARTEXT.finditer(body):
        last[(m.group(1), int(m.group(2)))] = dict(
            kind=m.group(1), x=int(m.group(2)), base=int(m.group(3)),
            fg=int(m.group(4)), bg=int(m.group(5)), tw=int(m.group(6)),
            t=m.group(7))
    rechtecke = {}
    for m in BARRECT.finditer(body):
        rechtecke[(m.group(1) or m.group(2) or "btn", int(m.group(3)))] = (
            int(m.group(3)), int(m.group(4)),
            int(m.group(5)), int(m.group(6)))
    return ([t for t in last.values() if t["t"].strip()], bar,
            list(rechtecke.values()))


def parse(path, marke="settings: rect name=waa "):
    body = open(path, "rb").read().decode("latin1")
    cut = body.rfind(marke)
    while cut > 0 and not any(TEXT.search(z)
                              for z in body[cut:].splitlines()):
        vor = body.rfind(marke, 0, cut)
        if vor < 0:
            break
        cut = vor
    tail = body[cut:] if cut >= 0 else body
    out = []
    for raw in tail.splitlines():
        m = TEXT.search(raw)
        if not m:
            continue
        k = KURZ.search(raw)
        axm = re.search(r" ax=(-?\d+) ay=(-?\d+)", raw)
        out.append(dict(ax=int(axm.group(1)) if axm else None,
                        ay=int(axm.group(2)) if axm else None,
                        win=int(m.group(1)), kind=int(m.group(2)),
                        x=int(m.group(3)), base=int(m.group(4)),
                        fg=int(m.group(5)), bg=int(m.group(6)),
                        tw=int(m.group(7)), t=m.group(8),
                        nq=int(k.group(1)) if k else 0,
                        nv=int(k.group(2)) if k else 0))
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


def grund(pic, x0, y0, x1, y1):
    """Die haeufigste Farbe eines Ausschnitts -- der gemessene Grund.

    Fuer ein Fenster ist der Grund die Farbe, die das Programm gemeldet
    hat. Fuer die Leiste dieser Runde gilt das NICHT mehr: sie wird mit
    `taskbar_alpha` ueber das Hintergrundbild gemischt, also ist hinter
    der Schrift weder die Flaechenfarbe noch irgendeine andere Zahl,
    die irgendwo gemeldet waere. Die haeufigste Farbe unter der Zeile
    ist sie dagegen immer: Schrift bedeckt einen Bruchteil ihres
    Kastens, der Rest ist Grund.
    """
    zaehl = {}
    for y in range(max(y0, 0), min(y1, pic.h)):
        for x in range(max(x0, 0), min(x1, pic.w)):
            p = pic.at(x, y)
            if p is None:
                continue
            zaehl[p] = zaehl.get(p, 0) + 1
    if not zaehl:
        return None
    return max(zaehl, key=lambda k: zaehl[k])


LINE_RUN = 10


def _run(pic, x0, y, schritt, n, bg, tol):
    """Die Farbe eines einfarbigen Laufs von `n` Bildpunkten, oder None."""
    c = pic.at(x0, y)
    if c is None or near(c, bg, tol):
        return None
    for k in range(1, n):
        p = pic.at(x0 + k * schritt, y)
        if p is None or p != c:
            return None
    return c


def linien_probe(pic, texts, ox, oy, ww, asc, desc):
    """Wie viele Beschriftungen auf einer waagerechten Linie liegen."""
    treffer = 0
    bad_2 = []
    for t in texts:
        x = ox + t["x"]
        y0 = oy + t["base"] - asc
        y1 = oy + t["base"] + desc
        x1 = min(x + t["tw"], ox + ww)
        bg = grund(pic, x, y0, x1, y1)
        if bg is None:
            continue
        box = inkbox(pic, x, y0, x1, y1, bg, 10)
        if box is None:
            continue
        lo_x, lo_y, hi_x, hi_y = box[0], box[1], box[2], box[3]
        for y in range(lo_y, min(hi_y, oy + t["base"]) + 1):
            links = _run(pic, lo_x - 2, y, -1, LINE_RUN, bg, 10)
            if links is None:
                continue
            right = _run(pic, hi_x + 2, y, 1, LINE_RUN, bg, 10)
            if right is None or right != links:
                continue
            treffer += 1
            bad_2.append(
                "LINIE  '%s' bei %d,%d steht auf einer Linie der Farbe "
                "%02x%02x%02x (Zeile y=%d, %d Bildpunkte links und rechts "
                "einfarbig)"
                % (t["t"][:32], x, oy + t["base"], links[0], links[1],
                   links[2], y, LINE_RUN))
            break
    return treffer, bad_2


def taskbar_messen(pic, serial, asc, desc):
    """Dieselben drei Fragen, gestellt an die Taskleiste.

    Rueckgabe: (Zahl der Texte, gemessen, leer, abgeschnitten,
    ueberlappend, Liste der Befunde).
    """
    texts, bar, rechtecke = parse_bar(serial)
    if bar is None:
        return 0, 0, 0, 0, 0, ["LEISTE keine `taskbar: STEHT`-Zeile "
                               "im Mitschnitt -- uitrace aus?"]
    bad_2 = []
    boxes = []
    empty_2 = 0
    for t in sorted(texts, key=lambda t: t["x"]):
        x = bar["x"] + t["x"]
        y0 = bar["y"] + t["base"] - asc
        y1 = bar["y"] + t["base"] + desc
        x1 = x + t["tw"]
        bg = grund(pic, x, y0, min(x1, bar["x"] + bar["w"]), y1)
        if bg is None:
            bg = rgb(t["bg"])
        box = inkbox(pic, x, y0, min(x1, bar["x"] + bar["w"]), y1, bg, 10)
        if box is None:
            empty_2 += 1
            bad_2.append(
                "LEISTE EMPTY  '%s' (%s) at %d,%d w=%d: no pixel differs "
                "from the measured ground %02x%02x%02x"
                % (t["t"][:32], t["kind"], x, bar["y"] + t["base"],
                   t["tw"], bg[0], bg[1], bg[2]))
            continue
        boxes.append((t["kind"] + ":" + t["t"], box, x, x1))
    ab = 0
    for name, b, x, x1 in boxes:
        if (x < bar["x"] or x1 > bar["x"] + bar["w"]
                or b[1] < bar["y"] or b[3] >= bar["y"] + bar["h"]):
            ab += 1
            bad_2.append("LEISTE CUT    '%s' at %d..%d (ink %s) leaves "
                            "the bar %d,%d %dx%d"
                            % (name[:32], x, x1, b[:4], bar["x"], bar["y"],
                               bar["w"], bar["h"]))
    for t in texts:
        own = None
        for rx, ry, rw, rh in rechtecke:
            if (rw > 0 and t["x"] >= rx and t["x"] < rx + rw
                    and t["base"] > ry and t["base"] <= ry + rh):
                if own is None or rw < own[2]:
                    own = (rx, ry, rw, rh)
        if own is None:
            continue
        if t["x"] + t["tw"] > own[0] + own[2]:
            ab += 1
            bad_2.append(
                "LEISTE CUT    '%s' meldet x=%d tw=%d und reicht damit "
                "%d Bildpunkte ueber sein Bedienelement %d,%d %dx%d hinaus"
                % (t["t"][:24], t["x"], t["tw"],
                   t["x"] + t["tw"] - own[0] - own[2],
                   own[0], own[1], own[2], own[3]))
    over_2 = 0
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = boxes[i][1], boxes[j][1]
            if a[0] > b[2] or b[0] > a[2] or a[1] > b[3] or b[1] > a[3]:
                continue
            if not (a[5] & b[5]):
                continue
            over_2 += 1
            bad_2.append("LEISTE OVER   '%s' %s and '%s' %s"
                            % (boxes[i][0][:24], a[:4],
                               boxes[j][0][:24], b[:4]))
    return len(texts), len(boxes), empty_2, ab, over_2, bad_2


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    pic = Pic(argv[1])
    marke = "settings: rect name=waa "
    for a in argv[3:]:
        if a.startswith("--cut="):
            marke = a[6:]
    texts, wins, font = parse(argv[2], marke)
    ox = oy = 0
    forced = False
    ww, wh = pic.w, pic.h
    want_win = None
    leiste = False
    linien = False
    knoepfe = False
    for a in argv[3:]:
        if a.startswith("--window="):
            ox, oy, ww, wh = (int(v) for v in a.split("=", 1)[1].split(","))
            forced = True
        elif a.startswith("--win="):
            want_win = int(a.split("=", 1)[1])
        elif a == "--leiste":
            leiste = True
        elif a == "--linien":
            linien = True
        elif a == "--knoepfe":
            knoepfe = True
    if want_win is None and texts:
        count = {}
        for t in texts:
            count[t["win"]] = count.get(t["win"], 0) + 1
        want_win = max(count, key=lambda k: count[k])
    texts = [t for t in texts if t["win"] == want_win and t["t"].strip()]
    last = {}
    for t in texts:
        last[(t["kind"], t["t"])] = t
    texts = list(last.values())

    if not forced and want_win in wins:
        w = wins[want_win]
        ox, oy, ww, wh = w["cx"], w["cy"], w["w"], w["h"]
    elif not forced and texts and texts[0].get("ax") is not None:
        ox, oy = texts[0]["ax"], texts[0]["ay"]
    asc, desc = font if font else (16, 6)
    bad = []
    boxes = []
    empty = 0
    ausserhalb = 0
    verdeckt = 0
    sicht = []
    _bt, bar, _br = parse_bar(argv[2])
    for t in texts:
        y0 = oy + t["base"] - asc
        y1 = oy + t["base"] + desc
        x = ox + t["x"]
        x1 = x + t["tw"]
        if y0 >= pic.h or y1 <= 0 or x >= pic.w or x1 <= 0:
            ausserhalb += 1
            bad.append("AUSSEN '%s' at %d,%d liegt ausserhalb des Schirms "
                       "%dx%d" % (t["t"][:32], x, oy + t["base"],
                                  pic.w, pic.h))
            continue
        if (bar is not None
                and y0 >= bar["y"] and y1 <= bar["y"] + bar["h"]
                and x >= bar["x"] and x1 <= bar["x"] + bar["w"]):
            verdeckt += 1
            bad.append("VERDECKT '%s' at %d,%d liegt unter der Leiste "
                       "%d,%d %dx%d" % (t["t"][:32], x, oy + t["base"],
                                        bar["x"], bar["y"], bar["w"],
                                        bar["h"]))
            continue
        sicht.append(t)
    texts = sicht
    for t in texts:
        x = ox + t["x"]
        y0 = oy + t["base"] - asc
        y1 = oy + t["base"] + desc
        x1 = x + t["tw"]
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
    gekuerzt = 0
    gk_tab = 0
    gk_fliess = 0
    for t in texts:
        if t["nv"] > t["nq"]:
            gekuerzt += 1
            if t["kind"] == 7:
                gk_tab += 1
            else:
                gk_fliess += 1
                bad.append("KURZ   '%s' (typ %d) malt %d von %d Oktetten"
                           % (t["t"][:32], t["kind"], t["nq"], t["nv"]))
            if not t["t"].endswith("..."):
                cut += 1
                bad.append("CLIP   '%s' painted %d of %d octets without a "
                           "mark -- a silent cut" % (t["t"][:32], t["nq"],
                                                     t["nv"]))
    over = 0
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = boxes[i][1], boxes[j][1]
            if a[0] > b[2] or b[0] > a[2] or a[1] > b[3] or b[1] > a[3]:
                continue
            if not (a[5] & b[5]):
                continue
            over += 1
            if over <= 12:
                bad.append("OVER   '%s' %s and '%s' %s"
                           % (boxes[i][0][:24], a[:4],
                              boxes[j][0][:24], b[:4]))
    line_2, lbad = linien_probe(pic, texts, ox, oy, ww, asc, desc)
    bad.extend(lbad)
    roh = open(argv[2], "rb").read().decode("latin1")
    schnitt = roh.rfind(marke)
    kn, kohne, kueber, kbad = knoepfe_messen(
        pic, roh[schnitt:] if schnitt >= 0 else roh, ox, oy, ww, wh, bar,
        texts)
    bad.extend(kbad)
    print("shotcheck: win %s  texts %d  measured %d  empty %d  cut %d  "
          "overlapping %d  gekuerzt %d  reiterkurz %d  fliesskurz %d  "
          "ausserhalb %d  verdeckt %d  linie %d  knopf %d  ohnekante %d  "
          "ueberstand %d"
          % (want_win, len(texts), len(boxes), empty, cut, over, gekuerzt,
             gk_tab, gk_fliess, ausserhalb, verdeckt, line_2, kn, kohne,
             kueber))
    for line in bad[:30]:
        print("  " + line)
    bad_2 = 0
    if leiste:
        bn, bm, bleer, bab, bueber, bbad = taskbar_messen(
            pic, argv[2], asc, desc)
        print("shotcheck: leiste texts %d  measured %d  empty %d  cut %d  "
              "overlapping %d" % (bn, bm, bleer, bab, bueber))
        for line in bbad[:30]:
            print("  " + line)
        bad_2 = bleer + bab + bueber
    if linien:
        bad_2 = bad_2 + line_2
    if knoepfe:
        bad_2 = bad_2 + kohne + kueber
    return 0 if (empty == 0 and cut == 0 and over == 0
                 and bad_2 == 0) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
