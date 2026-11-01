#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import sys

try:
    from PIL import Image
except ImportError:
    print("PIL fehlt: pip3 install pillow", file=sys.stderr)
    sys.exit(2)


def reason_2(px, x0, y0, w, h):
    zaehl = {}
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            c = px[x, y]
            zaehl[c] = zaehl.get(c, 0) + 1
    return max(zaehl.items(), key=lambda kv: kv[1])[0]


def tinte(px, x0, y0, w, h, bg, schwelle):
    m = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            c = px[x0 + x, y0 + y]
            d = abs(c[0] - bg[0]) + abs(c[1] - bg[1]) + abs(c[2] - bg[2])
            if d > schwelle:
                m[y][x] = 1
    return m


def kasten(m, x0=None, x1=None):
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


def columns(m):
    h = len(m)
    w = len(m[0]) if h else 0
    return [any(m[y][x] for y in range(h)) for x in range(w)]


def buendel(voll, luecke):
    out = []
    run_2 = None
    empty_3 = 0
    for x, v in enumerate(voll):
        if v:
            if run_2 is None:
                run_2 = [x, x]
            else:
                run_2[1] = x
            empty_3 = 0
        else:
            if run_2 is not None:
                empty_3 += 1
                if empty_3 >= luecke:
                    out.append((run_2[0], run_2[1]))
                    run_2 = None
                    empty_3 = 0
    if run_2 is not None:
        out.append((run_2[0], run_2[1]))
    return out


def field_messen(px, x0, y0, w, h, name, args):
    bg = reason_2(px, x0, y0, w, h)
    m = tinte(px, x0, y0, w, h, bg, args.schwelle)
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
    voll = columns(m)
    bs = buendel(voll, args.luecke)
    sym = None
    txt = None
    if len(bs) >= 2:
        sym = kasten(m, bs[0][0], bs[0][1] + 1)
        txt = kasten(m, bs[1][0], bs[-1][1] + 1)
    elif len(bs) == 1:
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


def bericht(r, args, error):
    if r["leer"]:
        print("  %-14s FIELD EMPTY (no pixel stands out from the background)"
              % r["name"])
        error.append("%s: leer" % r["name"])
        return
    x0, y0, w, h = r["feld"]
    print("  %-14s field %dx%d at %d,%d   background %s"
          % (r["name"], w, h, x0, y0, r["grund"]))
    print("               gap left %d right %d top %d bottom %d"
          % (r["links"], r["rechts"], r["oben"], r["unten"]))
    if abs(r["links"] - r["rechts"]) > args.tol:
        print("               VERLETZT waagrecht: %d gegen %d"
              % (r["links"], r["rechts"]))
        error.append("%s: waagrecht %d/%d"
                      % (r["name"], r["links"], r["rechts"]))
    if abs(r["oben"] - r["unten"]) > args.tol:
        print("               VERLETZT senkrecht: %d gegen %d"
              % (r["oben"], r["unten"]))
        error.append("%s: senkrecht %d/%d"
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
            print("               VIOLATED share: %d%% does not lie"
                  " zwischen %d%% und %d%%"
                  % (anteil, args.min_anteil, args.max_anteil))
            error.append("%s: anteil %d%%" % (r["name"], anteil))
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
            error.append("%s: mitte %.1f" % (r["name"], d))
        spacing_2 = t[0] - s[2] - 1
        print("               Abstand Symbol->Text %d" % spacing_2)


def lines_find(px, x0, y0, w, h, args):
    bg = reason_2(px, x0, y0, w, h)
    m = tinte(px, x0, y0, w, h, bg, args.schwelle)
    voll = [any(m[y][x] for x in range(w)) for y in range(h)]
    out = []
    run_2 = None
    for y, v in enumerate(voll):
        if v and run_2 is None:
            run_2 = [y, y]
        elif v:
            run_2[1] = y
        elif run_2 is not None:
            out.append((run_2[0], run_2[1]))
            run_2 = None
    if run_2 is not None:
        out.append((run_2[0], run_2[1]))
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

    im = Image.open(args.image_2).convert("RGB")
    px = im.load()
    print("BILD %s  %dx%d" % (args.image_2, im.width, im.height))
    error = []

    felder = []
    for f in args.feld:
        name = "feld%d" % len(felder)
        if ":" in f:
            f, name = f.split(":", 1)
        x, y, w, h = [int(v) for v in f.split(",")]
        felder.append((x, y, w, h, name))

    if args.zeilen:
        x, y, w, h = [int(v) for v in args.zeilen.split(",")]
        zs = lines_find(px, x, y, w, h, args)
        print("ROWS in area %d,%d %dx%d: %d found"
              % (x, y, w, h, len(zs)))
        hoehen = [zh for (_, zh) in zs]
        for k, (zy, zh) in enumerate(zs):
            felder.append((x, zy, w, zh, "zeile%d" % k))
        if hoehen and max(hoehen) - min(hoehen) > 1:
            print("  VIOLATED: the rows differ in height:"
                  " %d bis %d" % (min(hoehen), max(hoehen)))
            error.append("zeilenhoehe %d..%d" % (min(hoehen), max(hoehen)))

    print("FELDER")
    for (x, y, w, h, name) in felder:
        if x < 0 or y < 0 or x + w > im.width or y + h > im.height:
            print("  %-14s lies outside the image" % name)
            error.append("%s: ausserhalb" % name)
            continue
        bericht(field_messen(px, x, y, w, h, name, args), args, error)

    print("ERGEBNIS %d Felder, %d Verletzungen"
          % (len(felder), len(error)))
    for f in error:
        print("  - " + f)
    if error and not args.only_messen:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
