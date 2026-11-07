#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys


def read_2(path_2):
    with open(path_2, "rb") as f:
        return f.read().decode("utf-8", "replace")


def ppm(path_2):
    d = open(path_2, "rb").read()
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


def band(path_2, height, von_bottom):
    w, h, px = ppm(path_2)
    s = {}
    for y in range(h - von_bottom, h, 2):
        for x in range(0, w, 4):
            k = (y * w + x) * 3
            c = (px[k], px[k + 1], px[k + 2])
            s[c] = s.get(c, 0) + 1
    return s


def i64(v):
    v = int(v)
    return v - (1 << 64) if v > (1 << 63) else v


def main():
    folder = sys.argv[1]
    SW = int(sys.argv[2])
    SH = int(sys.argv[3])
    t = read_2(os.path.join(folder, "serial.txt"))

    pass_ = []
    fail = []

    def ok(m):
        pass_.append(m)
        print("  OK    %s" % m)

    def bad(m):
        fail.append(m)
        print("  FAIL  %s" % m)

    print("== 0. DIE ARBEITSFLAECHE ==")
    mw = None
    for mw in re.finditer(
            r"wm: work x=(\d+) y=(\d+) w=(\d+) h=(\d+)\s+screen=(\d+)x(\d+)"
            r" struts=(\d+)", t):
        pass
    mt = None
    for mt in re.finditer(
            r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t):
        pass
    if mw is None:
        print("  NO `wm: work` line -- the measuring key F12 did not arrive.")
        print("  Without it nothing can be recomputed; the run is invalid.")
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
            ok("the work area ends at the bar (%d <= %d)"
               % (wy + wh, ty))
        else:
            bad("the work area reaches %d points into the bar"
                % (wy + wh - ty))
    else:
        ty = None
    print()

    print("== 1. IS THE BAR ON TOP? ==")
    bloecke = []
    for chunk in t.split("wm: work ")[1:]:
        fen = re.findall(
            r"wm: fen i=(\d+) id=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
            r" lay=(\d+) fl=(\d+) z=(\d+)", chunk)
        bloecke.append([tuple(int(v) for v in f_) for f_ in fen])
    print("   %d measuring points (F12) on the wire" % len(bloecke))

    def taskbar_ebene(blk):
        for (i_, id_, x, y, w, h, lay, fl, z) in blk:
            if w >= SW and h <= 100 and i64(y) >= SH - 200:
                return lay, id_
        return None, None

    def tiefe(blk):
        edge = ty if ty is not None else SH - 80
        t_ = 0
        for (i_, id_, x, y, w, h, lay, fl, z) in blk:
            if lay == 1 and i64(y) + h > edge:
                t_ = max(t_, i64(y) + h)
        return t_

    if bloecke:
        last_2 = max(bloecke, key=tiefe)
        lay_t, id_t = taskbar_ebene(last_2)
        if lay_t is None:
            print("   the bar cannot be recognised in the window list")
        else:
            print("   Leiste: id=%d Ebene=%d" % (id_t, lay_t))
            edge = ty if ty is not None else SH - 80
            bottom = [(i_, id_, x, y, w, h, lay, fl, z)
                     for (i_, id_, x, y, w, h, lay, fl, z) in last_2
                     if id_ != id_t and lay == 1
                     and i64(y) + h > edge]
            if bottom:
                for (i_, id_, x, y, w, h, lay, fl, z) in bottom:
                    print("   window id=%d is at y=%d, is %d high "
                          "-> Unterkante y=%d" % (id_, i64(y), h, i64(y) + h))
                    print("   that is %d points BELOW the bar's top edge "
                          "(y=%d) -- es wurde also NICHT geblockt"
                          % (i64(y) + h - edge, edge))
                    if lay < lay_t:
                        ok("id=%d lies BELOW the bar (%d < %d) "
                           "-- genau wie Windows" % (id_, lay, lay_t))
                    else:
                        bad("id=%d is on layer %d, the bar on %d "
                            "-- es wuerde sie verdecken" % (id_, lay, lay_t))
            else:
                print("   no window reaches below the bar "
                      "-- das Ziehen hat es nicht so weit gebracht")

    b1 = os.path.join(folder, "11-fenster-normal.ppm")
    b2 = os.path.join(folder, "12-unter-der-leiste.ppm")
    if os.path.exists(b1) and os.path.exists(b2):
        height = (SH - ty) if ty is not None else 80
        s1 = band(b1, SH, height)
        s2 = band(b2, SH, height)
        eq = sum(min(s1.get(c, 0), s2.get(c, 0))
                     for c in set(s1) | set(s2))
        gesamt = sum(s1.values())
        anteil = 100 * eq // max(gesamt, 1)
        print("   bar band in the image: %d%% of the points unchanged"
              % anteil)
        if anteil >= 98:
            ok("the bar is visibly unchanged after the drag")
        else:
            bad("the bar band changed by %d%% -- "
                "etwas deckt die Leiste zu" % (100 - anteil))
    print()

    print("== 2. VOLLBILD (F11) ==")
    voll = re.findall(
        r"wm: voll id=(\d+) an=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
        r" fl=(\d+) lay=(\d+)", t)
    if not voll:
        bad("no `wm: voll` line -- F11 did not toggle")
    else:
        for (id_, an, x, y, w, h, fl, lay) in voll:
            print("   id=%s an=%s  %s,%s %sx%s  fl=%s lay=%s"
                  % (id_, an, i64(x), i64(y), w, h, fl, lay))
        ein = [v for v in voll if v[1] == "1"]
        aus = [v for v in voll if v[1] == "0"]
        if ein:
            (id_, an, x, y, w, h, fl, lay) = ein[-1]
            if (i64(x), i64(y), int(w), int(h)) == (0, 0, SW, SH):
                ok("fullscreen covers the WHOLE screen (0,0 %dx%d)" % (SW, SH))
            else:
                bad("Vollbild ist %s,%s %sx%s statt 0,0 %dx%d"
                    % (i64(x), i64(y), w, h, SW, SH))
            if int(lay) >= 3:
                ok("fullscreen is on layer %s -- above the bar" % lay)
            else:
                bad("fullscreen is on layer %s -- the bar would stay in front"
                    % lay)
            if int(fl) & 2:
                ok("fullscreen has no decoration (F_NODECO)")
            else:
                bad("fullscreen still has frame/title (fl=%s)" % fl)
        if ein and aus:
            vor = None
            for blk in bloecke:
                for (i_, id2, x, y, w, h, lay, fl, z) in blk:
                    if str(id2) == ein[-1][0]:
                        vor = (i64(x), i64(y), w, h)
            (id_, an, x, y, w, h, fl, lay) = aus[-1]
            nach = (i64(x), i64(y), int(w), int(h))
            if vor is None:
                print("   no geometry reported before fullscreen")
            elif vor == nach:
                ok("back to EXACTLY the old geometry %s" % (nach,))
            else:
                bad("back to %s instead of %s" % (nach, vor))
            if int(lay) == 1:
                ok("after fullscreen back on the normal layer")
            else:
                bad("after fullscreen on layer %s instead of 1" % lay)
    print()

    print("== ERGEBNIS ==   %d OK, %d FAIL" % (len(pass_), len(fail)))
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
