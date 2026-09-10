#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/ausrichtung.py -- SITZT SYMBOL UND TEXT AUF EINER LINIE?

RUNDE ECHTHARDWARE-4, Punkt 6 aus Justins Nachmessung.  Er hat die
Belege aus ECHTHARDWARE-3 SELBST mit der Lupe vermessen und dabei
gefunden, was keine unserer Abnahmen gefunden hat:

    Leiste          obere Kante y=1401, Unterkante y=1440  ->  39 hoch
    Terminalsymbol  x 57..68, y 1416..1425  ->  12 x 10
    Startsymbol     x 12..69, y 1401..1437  ->  klebt bei x=12

Ein Symbol, das ein Viertel der Leistenhoehe fuellt, ist kein Geschmack
-- es ist eine Zahl.  Und eine Zahl, die ein Mensch mit der Lupe
ausmessen muss, wird beim naechsten Mal wieder niemand ausmessen.
DESHALB IST DIESE PRUEFUNG EIN WERKZEUG UND KEINE HANDARBEIT.

WAS ES MISST.  Es bekommt ein Bild und die RECHTECKE der Klickfelder
(die Leiste, der Starter, der Explorer und das Kontrollzentrum melden
sie ohnehin auf der seriellen Leitung -- deshalb muss hier nichts
geraten werden) und rechnet je Feld nach:

    Symbolkasten    das erste Tintenbuendel von links
    Textkasten      alles danach
    Abstand links / rechts / oben / unten des GANZEN Inhalts
    Mitte des Symbols (y) gegen Mitte des Textes (y)

DIE REGELN, gegen die geprueft wird (`--regel`):

    mitte      Symbolmitte und Textmitte hoechstens 1 Punkt auseinander
    waagrecht  Abstand links und rechts hoechstens 1 Punkt auseinander
    senkrecht  Abstand oben und unten hoechstens 1 Punkt auseinander
    anteil     Symbolhoehe zwischen `--min-anteil` und `--max-anteil`
               der Feldhoehe (Vorgabe 55 bis 75 Hundertstel)

Aufruf:

    python3 tools/design/ausrichtung.py BILD.png \\
        --feld 54,1401,60,39:terminal --feld 12,1401,58,39:start
    python3 tools/design/ausrichtung.py BILD.png \\
        --zeilen 40,300,320,220 --zeilenhoehe 28

Rueckgabe 0, wenn jede Regel haelt; sonst 1, und jede Verletzung steht
mit ihrer Zahl in der Ausgabe.
"""
import argparse
import sys

try:
    from PIL import Image
except ImportError:
    print("PIL fehlt: pip3 install pillow", file=sys.stderr)
    sys.exit(2)


def grund(px, x0, y0, w, h):
    """Die haeufigste Farbe des Feldes ist der Grund."""
    zaehl = {}
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            c = px[x, y]
            zaehl[c] = zaehl.get(c, 0) + 1
    return max(zaehl.items(), key=lambda kv: kv[1])[0]


def tinte(px, x0, y0, w, h, bg, schwelle):
    """Eine Maske: 1, wo sich der Bildpunkt vom Grund abhebt.

    Der Abstand ist die Summe der drei Kanalabstaende und nicht der
    euklidische -- er ist billiger und fuer ein Ja/Nein genauso gut.
    """
    m = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            c = px[x0 + x, y0 + y]
            d = abs(c[0] - bg[0]) + abs(c[1] - bg[1]) + abs(c[2] - bg[2])
            if d > schwelle:
                m[y][x] = 1
    return m


def kasten(m, x0=None, x1=None):
    """Der umschliessende Kasten der Tinte, ggf. auf Spalten begrenzt."""
    h = len(m)
    w = len(m[0]) if h else 0
    a = 0 if x0 is None else x0
    b = w if x1 is None else x1
    xs, ys = [], []
    for y in range(h):
        for x in range(a, b):
            if m[y][x]:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


def spalten(m):
    """Je Spalte: hat sie Tinte?"""
    h = len(m)
    w = len(m[0]) if h else 0
    return [any(m[y][x] for y in range(h)) for x in range(w)]


def buendel(voll, luecke):
    """Zusammenhaengende Spaltenbereiche, getrennt durch >= `luecke`
    leere Spalten."""
    out = []
    lauf = None
    leer = 0
    for x, v in enumerate(voll):
        if v:
            if lauf is None:
                lauf = [x, x]
            else:
                lauf[1] = x
            leer = 0
        else:
            if lauf is not None:
                leer += 1
                if leer >= luecke:
                    out.append((lauf[0], lauf[1]))
                    lauf = None
                    leer = 0
    if lauf is not None:
        out.append((lauf[0], lauf[1]))
    return out


def feld_messen(px, x0, y0, w, h, name, args):
    bg = grund(px, x0, y0, w, h)
    m = tinte(px, x0, y0, w, h, bg, args.schwelle)
    # RUNDE ECHTHARDWARE-4: DIE PILLE IST KEIN INHALT.
    #
    # Ein Fensterknopf der Taskleiste traegt an seiner unteren Kante
    # einen drei Punkte hohen Balken -- er sagt "dieses Fenster laeuft"
    # bzw. "es ist vorne" (`taskbar.pill`). Er gehoert absichtlich AN
    # DIE KANTE und nicht in die Mitte; ohne diese Zeilen zaehlte die
    # Pruefung ihn als Inhalt und meldete jedes Mal "unten 0" gegen
    # "oben 11". Das waere ein Fehlalarm ueber ein Bauteil, das genau
    # dort richtig sitzt.
    for r in range(max(0, h - args.rand_unten), h):
        for c in range(w):
            m[r][c] = 0
    for r in range(min(h, args.rand_oben)):
        for c in range(w):
            m[r][c] = 0
    ganz = kasten(m)
    if ganz is None:
        return {"name": name, "leer": True, "feld": (x0, y0, w, h)}
    gx0, gy0, gx1, gy1 = ganz
    voll = spalten(m)
    bs = buendel(voll, args.luecke)
    sym = None
    txt = None
    if len(bs) >= 2:
        sym = kasten(m, bs[0][0], bs[0][1] + 1)
        txt = kasten(m, bs[1][0], bs[-1][1] + 1)
    elif len(bs) == 1:
        # Nur EIN Buendel: entweder nur ein Symbol oder nur Text. Ein
        # Symbol ist annaehernd quadratisch, Text ist breiter als hoch.
        k = kasten(m, bs[0][0], bs[0][1] + 1)
        if (k[2] - k[0] + 1) <= (k[3] - k[1] + 1) * 2:
            sym = k
        else:
            txt = k
    return {
        "name": name,
        "leer": False,
        "feld": (x0, y0, w, h),
        "grund": bg,
        "inhalt": ganz,
        "sym": sym,
        "txt": txt,
        "links": gx0,
        "rechts": w - 1 - gx1,
        "oben": gy0,
        "unten": h - 1 - gy1,
    }


def bericht(r, args, fehler):
    if r["leer"]:
        print("  %-14s FELD LEER (kein Bildpunkt hebt sich vom Grund ab)"
              % r["name"])
        fehler.append("%s: leer" % r["name"])
        return
    x0, y0, w, h = r["feld"]
    print("  %-14s Feld %dx%d bei %d,%d   Grund %s"
          % (r["name"], w, h, x0, y0, r["grund"]))
    print("               Abstand links %d rechts %d oben %d unten %d"
          % (r["links"], r["rechts"], r["oben"], r["unten"]))
    if abs(r["links"] - r["rechts"]) > args.tol:
        print("               VERLETZT waagrecht: %d gegen %d"
              % (r["links"], r["rechts"]))
        fehler.append("%s: waagrecht %d/%d"
                      % (r["name"], r["links"], r["rechts"]))
    if abs(r["oben"] - r["unten"]) > args.tol:
        print("               VERLETZT senkrecht: %d gegen %d"
              % (r["oben"], r["unten"]))
        fehler.append("%s: senkrecht %d/%d"
                      % (r["name"], r["oben"], r["unten"]))
    s, t = r["sym"], r["txt"]
    if s:
        sw = s[2] - s[0] + 1
        sh = s[3] - s[1] + 1
        anteil = sh * 100 // h
        print("               Symbol %dx%d bei +%d,+%d  Mitte y %.1f"
              " (%d%% der Feldhoehe)"
              % (sw, sh, s[0], s[1], (s[1] + s[3]) / 2.0, anteil))
        if anteil < args.min_anteil or anteil > args.max_anteil:
            print("               VERLETZT anteil: %d%% liegt nicht"
                  " zwischen %d%% und %d%%"
                  % (anteil, args.min_anteil, args.max_anteil))
            fehler.append("%s: anteil %d%%" % (r["name"], anteil))
    if t:
        print("               Text  %dx%d bei +%d,+%d  Mitte y %.1f"
              % (t[2] - t[0] + 1, t[3] - t[1] + 1, t[0], t[1],
                 (t[1] + t[3]) / 2.0))
    if s and t:
        ms = (s[1] + s[3]) / 2.0
        mt = (t[1] + t[3]) / 2.0
        d = abs(ms - mt)
        print("               Mitte Symbol %.1f  Mitte Text %.1f"
              "  Unterschied %.1f" % (ms, mt, d))
        if d > args.tol:
            print("               VERLETZT mitte: %.1f Punkte" % d)
            fehler.append("%s: mitte %.1f" % (r["name"], d))
        abstand = t[0] - s[2] - 1
        print("               Abstand Symbol->Text %d" % abstand)


def zeilen_finden(px, x0, y0, w, h, args):
    """Ein Listenbereich in Zeilen zerlegen: Zeilen mit Tinte, getrennt
    durch leere Zeilen.  Damit misst dasselbe Werkzeug die Trefferliste
    des Startmenues, die Dateiliste des Explorers und die Kacheln des
    Kontrollzentrums, ohne dass jemand Zeilenhoehen abtippt."""
    bg = grund(px, x0, y0, w, h)
    m = tinte(px, x0, y0, w, h, bg, args.schwelle)
    voll = [any(m[y][x] for x in range(w)) for y in range(h)]
    out = []
    lauf = None
    for y, v in enumerate(voll):
        if v and lauf is None:
            lauf = [y, y]
        elif v:
            lauf[1] = y
        elif lauf is not None:
            out.append((lauf[0], lauf[1]))
            lauf = None
    if lauf is not None:
        out.append((lauf[0], lauf[1]))
    # Zeilen, die naeher als `--zeilenluecke` beieinander liegen,
    # gehoeren zusammen (ein Buchstabe mit Unterlaenge reisst sonst ab).
    zus = []
    for (a, b) in out:
        if zus and a - zus[-1][1] <= args.zeilenluecke:
            zus[-1] = (zus[-1][0], b)
        else:
            zus.append((a, b))
    return [(y0 + a, b - a + 1) for (a, b) in zus]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bild")
    ap.add_argument("--feld", action="append", default=[],
                    help="x,y,b,h[:name] -- ein Klickfeld")
    ap.add_argument("--zeilen", default=None,
                    help="x,y,b,h -- ein Listenbereich, der in Zeilen"
                         " zerlegt wird")
    ap.add_argument("--schwelle", type=int, default=60,
                    help="ab welchem Farbabstand ein Punkt Tinte ist")
    ap.add_argument("--luecke", type=int, default=3,
                    help="so viele leere Spalten trennen Symbol von Text")
    ap.add_argument("--zeilenluecke", type=int, default=2)
    ap.add_argument("--tol", type=float, default=1.0,
                    help="erlaubter Unterschied in Bildpunkten")
    ap.add_argument("--rand-unten", type=int, default=0,
                    dest="rand_unten",
                    help="so viele Zeilen am unteren Feldrand nicht"
                         " mitzaehlen (Zustandsbalken/Pille)")
    ap.add_argument("--rand-oben", type=int, default=0, dest="rand_oben")
    ap.add_argument("--min-anteil", type=int, default=55)
    ap.add_argument("--max-anteil", type=int, default=75)
    ap.add_argument("--nur-messen", action="store_true",
                    help="messen und berichten, aber nicht durchfallen")
    args = ap.parse_args()

    im = Image.open(args.bild).convert("RGB")
    px = im.load()
    print("BILD %s  %dx%d" % (args.bild, im.width, im.height))
    fehler = []

    felder = []
    for f in args.feld:
        name = "feld%d" % len(felder)
        if ":" in f:
            f, name = f.split(":", 1)
        x, y, w, h = [int(v) for v in f.split(",")]
        felder.append((x, y, w, h, name))

    if args.zeilen:
        x, y, w, h = [int(v) for v in args.zeilen.split(",")]
        zs = zeilen_finden(px, x, y, w, h, args)
        print("ZEILEN im Bereich %d,%d %dx%d: %d gefunden"
              % (x, y, w, h, len(zs)))
        hoehen = [zh for (_, zh) in zs]
        for k, (zy, zh) in enumerate(zs):
            felder.append((x, zy, w, zh, "zeile%d" % k))
        if hoehen and max(hoehen) - min(hoehen) > 1:
            print("  VERLETZT: die Zeilen sind unterschiedlich hoch:"
                  " %d bis %d" % (min(hoehen), max(hoehen)))
            fehler.append("zeilenhoehe %d..%d" % (min(hoehen), max(hoehen)))

    print("FELDER")
    for (x, y, w, h, name) in felder:
        if x < 0 or y < 0 or x + w > im.width or y + h > im.height:
            print("  %-14s liegt ausserhalb des Bildes" % name)
            fehler.append("%s: ausserhalb" % name)
            continue
        bericht(feld_messen(px, x, y, w, h, name, args), args, fehler)

    print("ERGEBNIS %d Felder, %d Verletzungen"
          % (len(felder), len(fehler)))
    for f in fehler:
        print("  - " + f)
    if fehler and not args.nur_messen:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
