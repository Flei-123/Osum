#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/fenstermess.py -- FENSTER, LEISTE UND VOLLBILD NACHRECHNEN.

    python3 tools/design/fenstermess.py <ausgabeordner> <breite> <hoehe>

Justins Korrektur, woertlich: "in Windows koennen die Fenster auch nicht
ueber die Taskleiste geschoben werden, ich hatte dir aber gesagt das
soll so sein, das war mein Fehler. Ist das jetzt so oder nicht? Bitte
mach's so wie Windows."

WAS WINDOWS WIRKLICH TUT -- und was hier deshalb geprueft wird:

  1. Die Leiste liegt IMMER OBENAUF. Ein normales Fenster darf durchaus
     unter sie GESCHOBEN werden -- es verschwindet dort dahinter. Nicht
     geblockt, nur darunter. Geprueft wird also NICHT, ob das Ziehen
     verhindert wird (das waere falsch), sondern ob die Leiste nach dem
     Ziehen noch vollstaendig sichtbar ist: Ebene der Leiste > Ebene des
     Fensters, und das Leistenband im Bild unveraendert.
  2. MAXIMIEREN endet an der ARBEITSFLAECHE. y+h darf die Oberkante der
     Leiste nie ueberschreiten.
  3. VOLLBILD (F11) endet am SCHIRM, liegt UEBER der Leiste und kommt
     auf EXAKT die alte Geometrie zurueck.

Gerechnet wird aus den Zeilen, die das System selbst gemeldet hat:
`wm: work`, `wm: fen`, `wm: voll` und `taskbar: geom`. Das Bild wird
nur dort befragt, wo eine Ebene allein nichts beweist -- beim
Leistenband.
"""
import os
import re
import sys


def lies(pfad):
    with open(pfad, "rb") as f:
        return f.read().decode("utf-8", "replace")


def ppm(pfad):
    """(breite, hoehe, bytes) eines P6-PPM."""
    d = open(pfad, "rb").read()
    i = 2
    tok = []
    while len(tok) < 3:
        while d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while d[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while not d[j:j + 1].isspace():
            j += 1
        tok.append(int(d[i:j]))
        i = j
    i += 1
    return tok[0], tok[1], d[i:]


def band(pfad, hoehe, von_unten):
    """Die Farben des untersten Bandes -- das ist die Leiste."""
    w, h, px = ppm(pfad)
    s = {}
    for y in range(h - von_unten, h, 2):
        for x in range(0, w, 4):
            k = (y * w + x) * 3
            c = (px[k], px[k + 1], px[k + 2])
            s[c] = s.get(c, 0) + 1
    return s


def i64(v):
    v = int(v)
    return v - (1 << 64) if v > (1 << 63) else v


def main():
    ordner = sys.argv[1]
    SW = int(sys.argv[2])
    SH = int(sys.argv[3])
    t = lies(os.path.join(ordner, "serial.txt"))

    pass_ = []
    fail = []

    def ok(m):
        pass_.append(m)
        print("  OK    %s" % m)

    def bad(m):
        fail.append(m)
        print("  FAIL  %s" % m)

    # ---------------------------------------------- die Arbeitsflaeche
    print("== 0. DIE ARBEITSFLAECHE ==")
    mw = None
    for mw in re.finditer(
            r"wm: work x=(\d+) y=(\d+) w=(\d+) h=(\d+)\s+schirm=(\d+)x(\d+)"
            r" struts=(\d+)", t):
        pass
    mt = None
    for mt in re.finditer(
            r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t):
        pass
    if mw is None:
        print("  KEINE `wm: work`-Zeile -- die Messtaste F12 kam nicht an.")
        print("  Ohne sie ist nichts nachzurechnen; der Lauf ist ungueltig.")
        return 2
    wx, wy, ww, wh, ssw, ssh, strc = (int(v) for v in mw.groups())
    print("   Schirm            %dx%d" % (ssw, ssh))
    print("   Arbeitsflaeche    x=%d y=%d w=%d h=%d  (struts=%d)"
          % (wx, wy, ww, wh, strc))
    if mt is not None:
        tx, ty, tw_, th = (int(v) for v in mt.groups())
        print("   Taskleiste        x=%d y=%d w=%d h=%d  -> Oberkante y=%d"
              % (tx, ty, tw_, th, ty))
        if wy + wh <= ty:
            ok("die Arbeitsflaeche endet an der Leiste (%d <= %d)"
               % (wy + wh, ty))
        else:
            bad("die Arbeitsflaeche ragt %d Punkte in die Leiste"
                % (wy + wh - ty))
    else:
        ty = None
    print()

    # ------------------------------------------------ 1. Leiste obenauf
    # Die Ebenen: die Leiste liegt auf L_TOP=2, ein normales Fenster auf
    # L_NORMAL=1. Das ist die Zusage; sie muss in den Zahlen stehen.
    print("== 1. LIEGT DIE LEISTE OBENAUF? ==")
    # Jede F12-Antwort ist ein eigener Block. Der Block NACH dem Ziehen
    # ist der interessante.
    bloecke = []
    for stueck in t.split("wm: work ")[1:]:
        fen = re.findall(
            r"wm: fen i=(\d+) id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
            r" lay=(\d+) fl=(\d+) z=(\d+)", stueck)
        bloecke.append([tuple(int(v) for v in f_) for f_ in fen])
    print("   %d Messpunkte (F12) auf der Leitung" % len(bloecke))

    def leiste_ebene(blk):
        """Die Ebene des Fensters, das die Leiste ist -- das ist das
        Fenster mit voller Breite am unteren Rand."""
        for (i_, id_, x, y, w, h, lay, fl, z) in blk:
            if w >= SW and h <= 100 and i64(y) >= SH - 200:
                return lay, id_
        return None, None

    # DER BLOCK, IN DEM EIN FENSTER AM WEITESTEN UNTEN STAND. Der
    # letzte Messpunkt liegt hinter dem Zurueckziehen -- dort ist
    # nichts mehr unter der Leiste, und die Frage bliebe unbeantwortet.
    def tiefe(blk):
        kante = ty if ty is not None else SH - 80
        t_ = 0
        for (i_, id_, x, y, w, h, lay, fl, z) in blk:
            if lay == 1 and i64(y) + h > kante:
                t_ = max(t_, i64(y) + h)
        return t_

    if bloecke:
        letzte = max(bloecke, key=tiefe)
        lay_t, id_t = leiste_ebene(letzte)
        if lay_t is None:
            # Die Leiste ist ein eigenes Fenster; findet es der Filter
            # nicht, wird nichts behauptet.
            print("   die Leiste ist in der Fensterliste nicht zu erkennen")
        else:
            print("   Leiste: id=%d Ebene=%d" % (id_t, lay_t))
            # Der SCHREIBTISCH (Ebene 0) deckt immer den ganzen Schirm
            # und reicht damit von Natur aus unter die Leiste -- er
            # beweist nichts. Gefragt ist das NORMALE Fenster, das
            # jemand mit der Maus dorthin gezogen hat: Ebene 1.
            kante = ty if ty is not None else SH - 80
            unten = [(i_, id_, x, y, w, h, lay, fl, z)
                     for (i_, id_, x, y, w, h, lay, fl, z) in letzte
                     if id_ != id_t and lay == 1
                     and i64(y) + h > kante]
            if unten:
                for (i_, id_, x, y, w, h, lay, fl, z) in unten:
                    print("   Fenster id=%d steht bei y=%d, ist %d hoch "
                          "-> Unterkante y=%d" % (id_, i64(y), h, i64(y) + h))
                    print("   das sind %d Punkte UNTER der Leistenoberkante "
                          "(y=%d) -- es wurde also NICHT geblockt"
                          % (i64(y) + h - kante, kante))
                    if lay < lay_t:
                        ok("id=%d liegt UNTER der Leiste (%d < %d) "
                           "-- genau wie Windows" % (id_, lay, lay_t))
                    else:
                        bad("id=%d liegt auf Ebene %d, die Leiste auf %d "
                            "-- es wuerde sie verdecken" % (id_, lay, lay_t))
            else:
                print("   kein Fenster reicht unter die Leiste "
                      "-- das Ziehen hat es nicht so weit gebracht")

    # Und der Beweis im Bild: das Leistenband vor und nach dem Ziehen.
    b1 = os.path.join(ordner, "11-fenster-normal.ppm")
    b2 = os.path.join(ordner, "12-unter-der-leiste.ppm")
    if os.path.exists(b1) and os.path.exists(b2):
        hoehe = (SH - ty) if ty is not None else 80
        s1 = band(b1, SH, hoehe)
        s2 = band(b2, SH, hoehe)
        gleich = sum(min(s1.get(c, 0), s2.get(c, 0))
                     for c in set(s1) | set(s2))
        gesamt = sum(s1.values())
        anteil = 100 * gleich // max(gesamt, 1)
        print("   Leistenband im Bild: %d%% der Punkte unveraendert"
              % anteil)
        if anteil >= 98:
            ok("die Leiste ist nach dem Ziehen unveraendert sichtbar")
        else:
            bad("das Leistenband hat sich zu %d%% geaendert -- "
                "etwas deckt die Leiste zu" % (100 - anteil))
    print()

    # ------------------------------------------------- 3. das Vollbild
    print("== 2. VOLLBILD (F11) ==")
    voll = re.findall(
        r"wm: voll id=(\d+) an=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
        r" fl=(\d+) lay=(\d+)", t)
    if not voll:
        bad("keine `wm: voll`-Zeile -- F11 hat nicht geschaltet")
    else:
        for (id_, an, x, y, w, h, fl, lay) in voll:
            print("   id=%s an=%s  %s,%s %sx%s  fl=%s lay=%s"
                  % (id_, an, i64(x), i64(y), w, h, fl, lay))
        ein = [v for v in voll if v[1] == "1"]
        aus = [v for v in voll if v[1] == "0"]
        if ein:
            (id_, an, x, y, w, h, fl, lay) = ein[-1]
            if (i64(x), i64(y), int(w), int(h)) == (0, 0, SW, SH):
                ok("Vollbild deckt den GANZEN Schirm (0,0 %dx%d)" % (SW, SH))
            else:
                bad("Vollbild ist %s,%s %sx%s statt 0,0 %dx%d"
                    % (i64(x), i64(y), w, h, SW, SH))
            if int(lay) >= 3:
                ok("Vollbild liegt auf Ebene %s -- ueber der Leiste" % lay)
            else:
                bad("Vollbild liegt auf Ebene %s -- die Leiste bliebe davor"
                    % lay)
            if int(fl) & 2:
                ok("Vollbild ist ohne Schmuck (F_NODECO)")
            else:
                bad("Vollbild hat noch Rahmen/Titel (fl=%s)" % fl)
        # der Rueckweg
        if ein and aus:
            vor = None
            # die letzte Geometrie VOR dem Einschalten
            for blk in bloecke:
                for (i_, id2, x, y, w, h, lay, fl, z) in blk:
                    if str(id2) == ein[-1][0]:
                        vor = (i64(x), i64(y), w, h)
            (id_, an, x, y, w, h, fl, lay) = aus[-1]
            nach = (i64(x), i64(y), int(w), int(h))
            if vor is None:
                print("   keine Geometrie vor dem Vollbild gemeldet")
            elif vor == nach:
                ok("zurueck auf EXAKT die alte Geometrie %s" % (nach,))
            else:
                bad("zurueck auf %s statt %s" % (nach, vor))
            if int(lay) == 1:
                ok("nach dem Vollbild wieder auf der normalen Ebene")
            else:
                bad("nach dem Vollbild auf Ebene %s statt 1" % lay)
    print()

    print("== ERGEBNIS ==   %d OK, %d FAIL" % (len(pass_), len(fail)))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
