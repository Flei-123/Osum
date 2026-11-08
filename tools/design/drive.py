#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    drive.py <monitor-socket> <serial.txt> <ausgabeverzeichnis> <drehbuch>
    wait <secs>            anhalten
    mark <regex>               remember how often the regex is on the serial line now
    warteneu <regex> [|| deadline] wait until the regex is on the serial line more often than at the last `mark`
    doppelauf <name>            dasselbe, zweimal
    key <name>                sendkey
    photo <name>                 screendump nach <output>/<name>.ppm
    tbbtn<N>        Fensterknopf N         (taskbar: btn i=N ...)
    calrect<N>      button N des Kalenders  (calpop: rect name=N ..., Bildschirmpixel)
    trayrect<NAME>  element NAME of the tray flyout (traypop: rect name=, screen pixels)
    oskrect<NAME>   key NAME of the on-screen keyboard (osk: rect name=), osktrect<NAME> element of the witness window
    lrect<N>        Widget N des Starters  (launcher: rect id=N ...)
"""
import faulthandler
import os
import re
import socket
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))
import shapechrome


SERIAL_SPLICE = re.compile(r"(?<=[^\n])wm: schlieren grow=\d+ alpha=\d+ blur=\d+ aus=\d+ unterpx=\d+\n")


def unsplice(text):
    return SERIAL_SPLICE.sub("", text)


def read_2(path_2):
    try:
        with open(path_2, "rb") as f:
            return unsplice(f.read().decode("latin1"))
    except OSError:
        return ""


class Fahrer:
    def __init__(self, sock, serial, out):
        self.serial = serial
        self.out = out
        self.s = None
        bis = time.time() + 120.0
        while time.time() < bis:
            try:
                s = socket.socket(socket.AF_UNIX)
                s.settimeout(5.0)
                s.connect(sock)
                self.s = s
                break
            except OSError:
                time.sleep(0.1)
        if self.s is None:
            raise SystemExit("kein Monitor an %s" % sock)
        time.sleep(0.3)
        self.clear()
        self.x, self.y = 0, 0
        self.corner()

    def clear(self):
        try:
            self.s.settimeout(0.4)
            end = time.time() + 3.0
            while time.time() < end:
                if not self.s.recv(65536):
                    break
        except OSError:
            pass
        finally:
            self.s.settimeout(5.0)

    fast = False
    FAST_GAP = 0.02

    def cmd(self, line):
        try:
            self.s.sendall((line + "\n").encode())
        except OSError as e:
            raise SystemExit("monitor write failed (%s): %s" % (e, line))
        if self.fast and line.startswith("mouse_"):
            time.sleep(self.FAST_GAP)
            return
        time.sleep(0.06)
        self.clear()

    def klickmess(self, x, y, muster, deadline):
        self.fahre(x, y)
        time.sleep(0.35)
        self.clear()
        self.brand(muster)
        t0 = time.time()
        self.cmd("mouse_button 1")
        time.sleep(0.05)
        self.cmd("mouse_button 0")
        r = re.compile(muster)
        while time.time() - t0 < deadline:
            if len(r.findall(read_2(self.serial))) > self.mark_n:
                return (time.time() - t0) * 1000.0
            time.sleep(0.02)
        return None

    ECKSCHRITTE = 32

    def corner(self):
        for _ in range(self.ECKSCHRITTE):
            self.cmd("mouse_move -120 -120")
        self.x, self.y = 0, 0

    def fahre(self, x, y):
        self.corner()
        dx, dy = x, y
        while dx > 0 or dy > 0:
            sx, sy = min(dx, 120), min(dy, 120)
            self.cmd("mouse_move %d %d" % (sx, sy))
            dx -= sx
            dy -= sy
        self.x, self.y = x, y

    def klick_nahe(self, x, y, mal=1, key_2=1, hold=0.05):
        dx, dy = x - self.x, y - self.y
        while dx or dy:
            sx = max(-120, min(120, dx))
            sy = max(-120, min(120, dy))
            self.cmd("mouse_move %d %d" % (sx, sy))
            dx -= sx
            dy -= sy
        self.x, self.y = x, y
        time.sleep(0.35)
        for _ in range(mal):
            self.cmd("mouse_button %d" % key_2)
            time.sleep(hold)
            self.cmd("mouse_button 0")
        time.sleep(1.2)

    def fahre_nahe(self, x, y):
        dx, dy = x - self.x, y - self.y
        while dx or dy:
            sx = max(-120, min(120, dx))
            sy = max(-120, min(120, dy))
            self.cmd("mouse_move %d %d" % (sx, sy))
            dx -= sx
            dy -= sy
        self.x, self.y = x, y
        time.sleep(0.6)

    def ziehe_nahe(self, x0, y0, x1, y1, schritte=8):
        dx, dy = x0 - self.x, y0 - self.y
        while dx or dy:
            sx = max(-120, min(120, dx))
            sy = max(-120, min(120, dy))
            self.cmd("mouse_move %d %d" % (sx, sy))
            dx -= sx
            dy -= sy
        self.x, self.y = x0, y0
        time.sleep(0.35)
        self.cmd("mouse_button 1")
        time.sleep(0.25)
        cx, cy = x0, y0
        for k in range(1, schritte + 1):
            zx = x0 + (x1 - x0) * k // schritte
            zy = y0 + (y1 - y0) * k // schritte
            ddx, ddy = zx - cx, zy - cy
            while ddx or ddy:
                sx = max(-120, min(120, ddx))
                sy = max(-120, min(120, ddy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                ddx -= sx
                ddy -= sy
            cx, cy = zx, zy
            time.sleep(0.15)
        self.x, self.y = cx, cy
        time.sleep(0.35)
        self.cmd("mouse_button 0")
        time.sleep(1.2)

    def ziehe_mit_photo(self, x0, y0, x1, y1, name, schritte=8):
        self.fahre(x0, y0)
        time.sleep(0.35)
        self.cmd("mouse_button 1")
        time.sleep(0.25)
        cx, cy = x0, y0
        halt = schritte // 2
        for k in range(1, schritte + 1):
            zx = x0 + (x1 - x0) * k // schritte
            zy = y0 + (y1 - y0) * k // schritte
            ddx, ddy = zx - cx, zy - cy
            while ddx or ddy:
                sx = max(-120, min(120, ddx))
                sy = max(-120, min(120, ddy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                ddx -= sx
                ddy -= sy
            cx, cy = zx, zy
            time.sleep(0.15)
            if k == halt and name:
                time.sleep(0.6)
                self.photo(name)
        self.x, self.y = cx, cy
        time.sleep(0.35)
        self.cmd("mouse_button 0")
        time.sleep(1.2)

    def schleppe_fotos(self, x0, y0, dx, dy, schritte, prefix, nach=2):
        out = []
        self.fahre(x0, y0)
        time.sleep(0.5)
        self.photo(prefix + "-00")
        out.append((prefix + "-00", x0, y0, "before"))
        self.cmd("mouse_button 1")
        time.sleep(0.4)
        self.photo(prefix + "-01")
        out.append((prefix + "-01", x0, y0, "down"))
        cx, cy = x0, y0
        for k in range(1, schritte + 1):
            zx = x0 + dx * k // schritte
            zy = y0 + dy * k // schritte
            ddx, ddy = zx - cx, zy - cy
            while ddx or ddy:
                sx = max(-120, min(120, ddx))
                sy = max(-120, min(120, ddy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                ddx -= sx
                ddy -= sy
            cx, cy = zx, zy
            time.sleep(0.5)
            nm = "%s-%02d" % (prefix, k + 1)
            self.photo(nm)
            out.append((nm, cx, cy, "drag"))
        self.x, self.y = cx, cy
        self.cmd("mouse_button 0")
        for k in range(nach):
            nm = "%s-r%d" % (prefix, k)
            self.photo(nm)
            out.append((nm, cx, cy, "release"))
        time.sleep(1.5)
        nm = prefix + "-end"
        self.photo(nm)
        out.append((nm, cx, cy, "end"))
        return out

    def klick(self, x, y, mal=1, key_2=1):
        self.fahre(x, y)
        time.sleep(0.35)
        for i in range(mal):
            self.cmd("mouse_button %d" % key_2)
            if mal == 1:
                time.sleep(0.05)
            self.cmd("mouse_button 0")
        time.sleep(1.2)

    def ziehe(self, x0, y0, x1, y1, schritte=8):
        self.fahre(x0, y0)
        time.sleep(0.35)
        self.cmd("mouse_button 1")
        time.sleep(0.25)
        cx, cy = x0, y0
        for k in range(1, schritte + 1):
            zx = x0 + (x1 - x0) * k // schritte
            zy = y0 + (y1 - y0) * k // schritte
            dx, dy = zx - cx, zy - cy
            while dx or dy:
                sx = max(-120, min(120, dx))
                sy = max(-120, min(120, dy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                dx -= sx
                dy -= sy
            cx, cy = zx, zy
            time.sleep(0.15)
        self.x, self.y = cx, cy
        time.sleep(0.35)
        self.cmd("mouse_button 0")
        time.sleep(1.2)

    def ziehe_halt(self, x0, y0, x1, y1, halt, photo=None, esc=False, schritte=8):
        self.fahre(x0, y0)
        time.sleep(0.35)
        self.cmd("mouse_button 1")
        time.sleep(0.25)
        cx, cy = x0, y0
        for k in range(1, schritte + 1):
            zx = x0 + (x1 - x0) * k // schritte
            zy = y0 + (y1 - y0) * k // schritte
            ddx, ddy = zx - cx, zy - cy
            while ddx or ddy:
                sx = max(-120, min(120, ddx))
                sy = max(-120, min(120, ddy))
                self.cmd("mouse_move %d %d" % (sx, sy))
                ddx -= sx
                ddy -= sy
            cx, cy = zx, zy
            time.sleep(0.15)
        self.x, self.y = cx, cy
        time.sleep(halt)
        if photo:
            self.photo(photo)
        if esc:
            self.cmd("sendkey esc")
            time.sleep(0.5)
        self.cmd("mouse_button 0")
        time.sleep(1.2)

    def key_2(self, name):
        self.cmd("sendkey %s" % name)
        time.sleep(0.4)

    def warteauf(self, muster, deadline=25.0):
        r = re.compile(muster)
        bis = time.time() + deadline
        while time.time() < bis:
            if r.search(read_2(self.serial)):
                return True
            time.sleep(0.2)
        return False

    def brand(self, muster):
        self.brand_muster = re.compile(muster)
        self.mark_n = len(self.brand_muster.findall(read_2(self.serial)))

    def warteneu(self, muster, deadline=25.0):
        r = re.compile(muster)
        n0 = getattr(self, "mark_n", 0)
        bis = time.time() + deadline
        while time.time() < bis:
            if len(r.findall(read_2(self.serial))) > n0:
                return True
            time.sleep(0.2)
        return False

    def photo(self, name, deadline=30.0):
        target = os.path.join(self.out, name + ".ppm")
        if os.path.exists(target):
            os.unlink(target)
        self.cmd("screendump %s" % target)
        last_2, ruhig = -1, 0
        bis = time.time() + deadline
        while time.time() < bis:
            time.sleep(0.15)
            try:
                now = os.path.getsize(target)
            except OSError:
                continue
            if now == last_2 and now > 0:
                ruhig += 1
                if ruhig >= 3:
                    print("foto %s %d Oktette" % (name, now))
                    return True
            else:
                ruhig, last_2 = 0, now
        print("foto %s FEHLGESCHLAGEN" % name)
        return False

    def serie(self, mode, n, name, deadline=60.0, pace_ms=0):
        cmds = []
        if mode == "click":
            cmds += ["mouse_button 1", "mouse_button 0"]
        elif mode.startswith("key:"):
            cmds.append("sendkey %s" % mode[4:])
        elif mode.startswith("drag:"):
            dgx, dgy, dgp = (int(v) for v in mode[5:].split(","))
            cmds.append("mouse_button 1")
        paths = []
        for i in range(n):
            pth = os.path.join(self.out, "%s-%03d.ppm" % (name, i))
            if os.path.exists(pth):
                os.unlink(pth)
            paths.append(pth)
            if mode.startswith("drag:"):
                sg = 1 if (i // dgp) % 2 == 0 else -1
                cmds.append("mouse_move %d %d" % (sg * dgx, sg * dgy))
            if mode == "move":
                cmds.append("mouse_move %d 0" % (6 if i % 2 == 0 else -6))
            cmds.append("screendump %s" % pth)
        if mode.startswith("drag:"):
            cmds.append("mouse_button 0")
        if pace_ms > 0:
            for c in cmds:
                self.s.sendall((c + "\n").encode())
                if c.startswith("screendump"):
                    time.sleep(pace_ms / 1000.0)
        else:
            self.s.sendall(("\n".join(cmds) + "\n").encode())
        bis = time.time() + deadline
        for pth in paths:
            last_2, ruhig = -1, 0
            while time.time() < bis:
                time.sleep(0.1)
                try:
                    now = os.path.getsize(pth)
                except OSError:
                    continue
                if now == last_2 and now > 0:
                    ruhig += 1
                    if ruhig >= 2:
                        break
                else:
                    ruhig, last_2 = 0, now
            else:
                print("serie %s FAILED at %s" % (name, pth))
                self.clear()
                return False
        self.clear()
        print("serie %s: %d frames" % (name, n))
        return True

    def window(self, prog):
        t = read_2(self.serial)
        m = None
        for m in re.finditer(
                r"%s: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % prog, t):
            pass
        if m is None:
            return None
        if prog == "launcher":
            return (int(m.group(1)), int(m.group(2)))
        b, th = self.chrome()
        if re.search(r"%s: strip h=\d+" % prog, t):
            th = b
            k = t.rfind("wm: fenliste")
            if k >= 0:
                for w in re.finditer(r"wm: fen i=\d+ id=\d+ x=(\d+) y=(\d+) w=\d+ h=\d+ lay=\d+ fl=(\d+) ", t[k:]):
                    if int(w.group(3)) & 64:
                        return (int(w.group(1)) + b, int(w.group(2)) + th)
        return (int(m.group(1)) + b, int(m.group(2)) + th)

    def chrome(self):
        if getattr(self, "_chrome", None):
            return self._chrome
        self._chrome = shapechrome.client_inset(self.out)
        return self._chrome

    def fenstergeom(self, wid):
        t = read_2(self.serial)
        m = None
        for m in re.finditer(
                r"wm: fen i=\d+ id=%d x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % wid,
                t):
            pass
        if m is None:
            return None
        x, y, w, h = (int(m.group(i)) for i in (1, 2, 3, 4))
        if x > (1 << 63):
            x -= (1 << 64)
        if y > (1 << 63):
            y -= (1 << 64)
        sk = 1
        g = None
        for g in re.finditer(r"taskbar: geom edge=\d+ x=\d+ y=\d+ w=\d+ h=(\d+)", t):
            pass
        if g is not None and int(g.group(1)) >= 60:
            sk = 2
        b, th = self.chrome()
        return (x, y, w, h, b * sk, th * sk)

    def fokus_id(self):
        t = read_2(self.serial)
        m = None
        for m in re.finditer(r"wm: fokus id=(\d+) vor=\d+", t):
            pass
        if m is None:
            return None
        return int(m.group(1))

    def rechteck(self, name):
        t = read_2(self.serial)

        def last_2(muster):
            m = None
            for m in re.finditer(muster, t):
                pass
            return m

        if name in ("cap_min", "cap_max", "cap_close"):
            fen = []
            k = t.rfind("wm: fenliste")
            tt = t[k:] if k >= 0 else t
            last = []
            for m in re.finditer(r"wm: fen i=(\d+) id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+) lay=\d+ "
                                 r"fl=(\d+) z=(\d+) [^\n]*? bar=(\d+) capw=(\d+) fr=(\d+)", tt):
                x_, y_, w_, h_, fl_, z_, bar_, capw_, fr_ = (int(v) for v in m.groups()[1:])
                if fl_ & 1 == 0:
                    last.append((x_, y_, w_, h_, z_, bar_, capw_, fr_))
            fen = last
            if not fen:
                return None
            x, y, w, h, z, bar, capw, fr = max(fen, key=lambda r: r[4])
            ow = w + 2 * fr
            n = {"cap_min": 0, "cap_max": 1, "cap_close": 2}[name]
            return (x + ow - fr - 3 * capw + n * capw, y + fr, capw, bar)
        if name in ("start_alle", "start_zurueck", "start_power", "start_feld"):
            n_ = {"start_alle": 5, "start_zurueck": 6, "start_power": 4, "start_feld": 1}[name]
            m = last_2(r"launcher: rect id=%d kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % n_)
            g = last_2(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None or g is None:
                return None
            return (int(g.group(1)) + int(m.group(1)), int(g.group(2)) + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("start_row"):
            n_ = int(name[9:])
            m = last_2(r"launcher: rect id=2 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            g = last_2(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            z = last_2(r"launcher: rows x=\d+ base=\d+ zh=(\d+)")
            if m is None or g is None or z is None:
                return None
            zh = int(z.group(1))
            return (int(g.group(1)) + int(m.group(1)), int(g.group(2)) + int(m.group(2)) + n_ * zh,
                    int(m.group(3)), zh)
        if name.startswith("start_"):
            m = last_2(r"launcher: tile i=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)\s+name=\[%s\]"
                       % re.escape(name[6:]))
            g = last_2(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None or g is None:
                return None
            return (int(g.group(1)) + int(m.group(1)), int(g.group(2)) + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("qskachel"):
            n = int(name[8:])
            m = last_2(r"qs: kachel n=%d slot=\d+ x=(\d+) y=(\d+) "
                       r"w=(\d+) h=(\d+) an=\d+" % n)
            g = last_2(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None or g is None:
                return None
            return (int(g.group(1)) + int(m.group(1)),
                    int(g.group(2)) + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("qsnetkey"):
            key = int(name[8:])
            m = last_2(r"qsnet: box k=%d x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % key)
            g = last_2(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None or g is None:
                return None
            return (int(g.group(1)) + int(m.group(1)), int(g.group(2)) + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name in ("qsmprev", "qsmplay", "qsmnext"):
            word = {"qsmprev": "mprev", "qsmplay": "mplay", "qsmnext": "mnext"}[name]
            m = last_2(r"qs: %s +x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % word)
            g = last_2(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None or g is None:
                return None
            return (int(g.group(1)) + int(m.group(1)), int(g.group(2)) + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name in ("qstm", "qsset"):
            word_2 = "tm" if name == "qstm" else "set"
            m = last_2(r"qs: row %s y=(\d+) h=(\d+)" % word_2)
            g = last_2(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None or g is None:
                return None
            y0, hh = int(m.group(1)), int(m.group(2))
            return (int(g.group(1)) + 8, y0, int(g.group(3)) - 16, hh)
        if name == "hellspur":
            m = last_2(r"qs: bright trace from=(\d+) bis=(\d+) ym=(\d+)")
            if m is None:
                return None
            x0, x1, ym = (int(m.group(i)) for i in (1, 2, 3))
            return (x0, ym - 4, x1 - x0, 8)
        gm = last_2(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
        tb = (int(gm.group(1)), int(gm.group(2))) if gm else (0, 0)
        if name.startswith("pin") and not name[3:].isdigit():
            word_2 = name[3:]
            everything = list(re.finditer(
                r"taskbar: pin %s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % word_2, t))
            if not everything or tb is None:
                return None
            m = everything[-1]
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("pin") and name[3:].isdigit():
            k = int(name[3:])
            everything = list(re.finditer(
                r"taskbar: pin (\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t))
            if not everything:
                return None
            last = everything[-1].group(1)
            n = 1
            for m2 in reversed(everything[:-1]):
                if m2.group(1) == last:
                    break
                n += 1
            letzten = everything[-n:]
            if k >= len(letzten):
                return None
            m = letzten[k]
            return (tb[0] + int(m.group(2)), tb[1] + int(m.group(3)),
                    int(m.group(4)), int(m.group(5)))
        if name == "start":
            m = last_2(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name == "chevron":
            m = last_2(r"taskbar: chevron x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("traytile") and name[8:].isdigit():
            o = last_2(r"traypop: open n=\d+ x=(\d+) y=(\d+)")
            m = last_2(r"traypop: tile i=%s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % name[8:])
            if o is None or m is None:
                return None
            return (int(o.group(1)) + int(m.group(1)), int(o.group(2)) + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("ncrow") and name[5:].isdigit():
            m = last_2(r"notifc: card %s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % name[5:])
            if m is None:
                return None
            return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
        if name.startswith("ncsec") and name[5:].isdigit():
            m = last_2(r"notifc: btn %s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % name[5:])
            if m is None:
                return None
            return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
        if name == "toast":
            m = last_2(r"taskbar: toast \[.*\] x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
        if name == "glocke":
            m = last_2(r"taskbar: field noti x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("tbbtn"):
            n = int(name[5:])
            m = last_2(r"taskbar: btn i=%d id=\d+ x=(\d+) y=(\d+) "
                       r"w=(\d+) h=(\d+)" % n)
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name in ("netz", "uhr"):
            f = "net" if name == "netz" else "clock"
            m = last_2(r"taskbar: field %s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % f)
            if m is None:
                return None
            return (tb[0] + int(m.group(1)), tb[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("fmbar"):
            n = int(name[5:])
            m = last_2(r"explorer: rect id=%d kind=7 "
                       r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % n)
            o = self.window("explorer")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("dmenue"):
            n = int(name[6:])
            m = last_2(r"desktop: context open x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            zh = (int(m.group(4)) - 4) // 4
            return (int(m.group(1)) + 6, int(m.group(2)) + 2 + n * zh, max(8, int(m.group(3)) - 12), zh)
        if name.startswith("bmenue"):
            n = int(name[6:])
            m = last_2(r"taskbar: context empty x=(\d+) y=(\d+) w=(\d+) h=(\d+) n=(\d+)")
            if m is None:
                return None
            zh = (int(m.group(4)) - 4) // int(m.group(5))
            return (int(m.group(1)) + 6, int(m.group(2)) + 2 + n * zh, max(8, int(m.group(3)) - 12), zh)
        if name.startswith("emenue"):
            n = int(name[6:])
            m = last_2(r"explorer: menurect wx=(\d+) wy=(\d+) wh=(\d+)(?: zh=(\d+))?")
            if m is None:
                return None
            zh = int(m.group(4)) if m.group(4) else 20
            return (int(m.group(1)) + 8, int(m.group(2)) + 4 + n * zh, 90, zh)
        if name == "qsalle":
            g = last_2(r"qs: row set y=(\d+) x=(\d+) h=(\d+)")
            if g is not None:
                return (int(g.group(2)), int(g.group(1)), int(g.group(3)), int(g.group(3)))
            m = last_2(r"qs: open x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                m = last_2(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            if m is None:
                return None
            x, y = int(m.group(1)), int(m.group(2))
            w, h = int(m.group(3)), int(m.group(4))
            return (x + 10, y + h - 10 - 22, w - 20, 22)
        if name.startswith("trayrect"):
            m = last_2(r"traypop: rect name=%s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % re.escape(name[8:]))
            if m is None:
                return None
            return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
        if name.startswith("calrect"):
            m = last_2(r"calpop: rect name=%s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % re.escape(name[7:]))
            if m is None:
                return None
            return (int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
        if name.startswith("oskrect"):
            m = last_2(r"osk: rect name=%s x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)" % re.escape(name[7:]))
            if m is None:
                return None
            return (int(m.group(3)), int(m.group(4)), int(m.group(1)), int(m.group(2)))
        if name.startswith("osktrect"):
            m = last_2(r"osktest: rect name=%s x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)" % re.escape(name[8:]))
            if m is None:
                return None
            return (int(m.group(3)), int(m.group(4)), int(m.group(1)), int(m.group(2)))
        if name.startswith("vprect"):
            m = last_2(r"vplay: rect name=%s x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)" % re.escape(name[6:]))
            if m is None:
                return None
            return (int(m.group(3)), int(m.group(4)), int(m.group(1)), int(m.group(2)))
        if name.startswith("chrect"):
            m = last_2(r"charmap: rect name=%s x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)" % re.escape(name[6:]))
            if m is None:
                return None
            return (int(m.group(3)), int(m.group(4)), int(m.group(1)), int(m.group(2)))
        if name.startswith("lrect"):
            n = int(name[5:])
            m = last_2(r"launcher: rect id=%d kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % n)
            o = self.window("launcher")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("lzeile"):
            n = int(name[6:])
            m = last_2(r"launcher: rect id=2 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)\]")
            if m is None:
                m = last_2(r"launcher: rect id=2 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            z = last_2(r"launcher: rows x=\d+ base=\d+ zh=(\d+)")
            o = self.window("launcher")
            if m is None or z is None or o is None:
                return None
            zh = int(z.group(1))
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)) + n * zh,
                    int(m.group(3)), zh)
        if name.startswith("sreiter"):
            n = int(name[7:])
            m = last_2(r"settings: rect name=waa x=(\d+) y=(\d+) "
                       r"w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)")
            if m is None:
                return None
            w, h = int(m.group(3)), int(m.group(4))
            ax, ay = int(m.group(5)), int(m.group(6))
            o = (ax - int(m.group(1)), ay - int(m.group(2)))
            x, y = int(m.group(1)), int(m.group(2))
            tab = 11
            bx = x + (w * (2 * n + 1)) // (2 * tab)
            return (o[0] + bx - w // (2 * tab), o[1] + y,
                    w // tab, h)
        if name.startswith("srect"):
            k = name[5:]
            ms = last_2(r"settings: rect name=%s x=\d+ y=\d+ w=(\d+) h=(\d+) ax=(\d+) ay=(\d+)" % k)
            if ms is not None:
                return (int(ms.group(3)), int(ms.group(4)), int(ms.group(1)), int(ms.group(2)))
            m = last_2(r"settings: rect name=%s x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % k)
            o = self.window("settings")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("ftabzeile"):
            n = int(name[9:])
            m = last_2(r"explorer: rect id=\d+ kind=6 "
                       r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            z = last_2(r"explorer: rows x=\d+ base=\d+ zh=(\d+)(?: head=\d+ headh=(\d+))?")
            o = self.window("explorer")
            if m is None or z is None or o is None:
                return None
            zh = int(z.group(1))
            header = int(z.group(2)) if z.group(2) else zh + 4
            y0 = int(m.group(2)) + header + 2 + n * zh
            return (o[0] + int(m.group(1)), o[1] + y0, int(m.group(3)), zh)
        if name.startswith("fkante"):
            n = int(name[6:])
            sp = last_2(r"explorer: columns (\d+) (\d+) (\d+) (\d+)")
            m = last_2(r"explorer: rect id=\d+ kind=6 "
                       r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
            o = self.window("explorer")
            if sp is None or m is None or o is None or n > 2:
                return None
            ex = int(sp.group(n + 2)) - 10
            return (o[0] + ex, o[1] + int(m.group(2)) + 14, 0, 0)
        if name in ("ftab", "fbaum"):
            art = 6 if name == "ftab" else 5
            m = last_2(r"explorer: rect id=\d+ kind=%d "
                       r"x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % art)
            o = self.window("explorer")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("fvrect") or name.startswith("fvpt"):
            nm = name[6:] if name.startswith("fvrect") else "view"
            m = last_2(r"fvviewer: rect name=%s x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)" % nm)
            o = self.window("fvviewer")
            if m is None or o is None:
                return None
            rx, ry, rw_, rh_ = (int(m.group(i)) for i in (1, 2, 3, 4))
            if name.startswith("fvpt"):
                fa, fb = name[4:].split("x")
                return (o[0] + rx + rw_ * int(fa) // 100, o[1] + ry + rh_ * int(fb) // 100, 0, 0)
            return (o[0] + rx, o[1] + ry, rw_, rh_)
        if name.startswith("mailrect") or name.startswith("mailpt"):
            nm = name[8:] if name.startswith("mailrect") else "list"
            m = last_2(r"mail: rect name=%s x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)" % nm)
            o = self.window("mail")
            if m is None or o is None:
                return None
            rx, ry, rw_, rh_ = (int(m.group(i)) for i in (1, 2, 3, 4))
            if name.startswith("mailpt"):
                fa, fb = name[6:].split("x")
                return (o[0] + rx + rw_ * int(fa) // 100, o[1] + ry + rh_ * int(fb) // 100, 0, 0)
            return (o[0] + rx, o[1] + ry, rw_, rh_)
        if name.startswith("wlnth"):
            kind, idx = (int(v) for v in name[5:].split("x"))
            rows = [tuple(int(v) for v in g) for g in re.findall(
                r"welcome: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)]
            start = 0
            for i in range(1, len(rows)):
                if rows[i][0] <= rows[i - 1][0]:
                    start = i
            batch = [r for r in rows[start:] if r[1] == kind]
            o = self.window("welcome")
            if o is None or not -len(batch) <= idx < len(batch):
                return None
            r = batch[idx]
            return (o[0] + r[2], o[1] + r[3], r[4], r[5])
        if name.startswith("fdnth"):
            kind, idx = (int(v) for v in name[5:].split("x"))
            rows = [tuple(int(v) for v in g) for g in re.findall(
                r"freunde: rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)", t)]
            start = 0
            for i in range(1, len(rows)):
                if rows[i][0] <= rows[i - 1][0]:
                    start = i
            batch = [r for r in rows[start:] if r[1] == kind]
            o = self.window("freunde")
            if o is None or not -len(batch) <= idx < len(batch):
                return None
            r = batch[idx]
            return (o[0] + r[2], o[1] + r[3], r[4], r[5])
        if name.startswith("fdrect"):
            n = int(name[6:])
            m = last_2(r"freunde: rect id=%d kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % n)
            o = self.window("freunde")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        if name.startswith("frect"):
            n = int(name[5:])
            m = last_2(r"explorer: rect id=%d kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % n)
            o = self.window("explorer")
            if m is None or o is None:
                return None
            return (o[0] + int(m.group(1)), o[1] + int(m.group(2)),
                    int(m.group(3)), int(m.group(4)))
        return None


def main():
    wd = int(os.environ.get("DRIVE_WATCHDOG", "1800") or 0)
    if wd > 0:
        faulthandler.dump_traceback_later(wd, exit=True)
    if len(sys.argv) < 5:
        print(__doc__)
        return 2
    sock, serial, out, buch = sys.argv[1:5]
    os.makedirs(out, exist_ok=True)
    f = Fahrer(sock, serial, out)
    error = 0
    base_gap = float(os.environ.get("DRIVE_TIPPE_GAP", "0.12"))
    tippe_gap = base_gap
    for roh in open(buch, encoding="utf-8"):
        z = roh.strip()
        if not z or z.startswith("#"):
            continue
        parts = z.split(None, 1)
        b = parts[0]
        arg = parts[1].strip() if len(parts) > 1 else ""
        if b == "killstarter":
            pids = re.findall(r"launcher: pid=(\d+)",
                              open(serial, errors="replace").read())
            if not pids:
                print("killstarter: no launcher pid on the serial line")
                error += 1
                continue
            b = "tippe"
            arg = "kill %s" % pids[-1]
            tippe_gap = 0.4
        if b == "killlast":
            pids = re.findall(r"launcher: start (?!refused)[^\n]*? pid=(\d+)",
                              open(serial, errors="replace").read())
            if not pids:
                print("killlast: no started program on the serial line")
                error += 1
                continue
            b = "tippe"
            arg = "kill %s" % pids[-1]
            tippe_gap = 0.4
        if b == "warte":
            time.sleep(float(arg))
        elif b == "marke":
            f.brand(arg.strip().strip("'\""))
        elif b == "schnell":
            f.fast = arg.strip() == "an"
            print("schnell %s" % ("an" if f.fast else "aus"))
        elif b == "klickmess":
            head, _, tail = arg.partition(" | ")
            muster, _, dl = tail.partition("||")
            muster = muster.strip().strip("'\"")
            r = f.rechteck(head.strip())
            if r is None:
                print("klickmess %s -> NO RECT REPORTED" % head.strip())
                error += 1
                continue
            ms = f.klickmess(r[0] + r[2] // 2, r[1] + r[3] // 2, muster, float(dl) if dl.strip() else 30.0)
            if ms is None:
                print("klickmess %s -> NOT THERE" % head.strip())
                error += 1
            else:
                print("klickmess %s -> %d ms" % (head.strip(), ms))
            time.sleep(0.5)
        elif b == "warteneu":
            st = arg.split("||")
            muster = st[0].strip().strip("'\"")
            t0 = time.time()
            ok = f.warteneu(muster, float(st[1]) if len(st) > 1 else 25.0)
            print("warteneu %s -> %s (%.2f s)" % (muster, "da" if ok else "NICHT DA", time.time() - t0))
            if not ok:
                error += 1
        elif b in ("warteauf", "warteaufmuss"):
            st = arg.split("||")
            muster = st[0].strip().strip("'\"")
            ok = f.warteauf(muster, float(st[1]) if len(st) > 1 else 25.0)
            print("warteauf %s -> %s" % (muster, "da" if ok else "NICHT DA"))
            if not ok:
                error += 1
                if b == "warteaufmuss":
                    print("ABBRUCH: %s ist Voraussetzung" % muster)
                    break
        elif b == "halte":
            x, y = (int(v) for v in arg.split(","))
            f.fahre(x, y)
            time.sleep(0.35)
            f.cmd("mouse_button 1")
            time.sleep(0.6)
        elif b == "halteauf":
            r = f.rechteck(arg)
            if r is None:
                print("halteauf %s: kein Rechteck gemeldet" % arg)
                error += 1
            else:
                f.fahre_nahe(r[0] + r[2] // 2, r[1] + r[3] // 2)
                time.sleep(0.35)
                f.cmd("mouse_button 1")
                time.sleep(0.6)
        elif b == "rad":
            n = int(arg)
            for _ in range(abs(n)):
                f.cmd("mouse_move 0 0 %d" % (1 if n > 0 else -1))
                time.sleep(0.15)
            time.sleep(0.6)
        elif b == "loslassen":
            f.cmd("mouse_button 0")
            time.sleep(1.2)
        elif b in ("klick", "doppel", "fahre", "rklick"):
            x, y = (int(v) for v in arg.split(","))
            if b == "fahre":
                f.fahre(x, y)
            elif b == "rklick":
                f.klick(x, y, 1, key_2=2)
            else:
                f.klick(x, y, 2 if b == "doppel" else 1)
        elif b == "wische":
            t = arg.split()
            n = int(t[0])
            sdx, sdy = (int(v) for v in t[1].split(","))
            for k in range(n):
                sg = 1 if (k // 20) % 2 == 0 else -1
                f.cmd("mouse_move %d %d" % (sg * sdx, sg * sdy))
        elif b in ("moveby", "clickby"):
            x, y = (int(v) for v in arg.split(","))
            if b == "moveby":
                f.fahre_nahe(x, y)
            else:
                f.klick_nahe(x, y)
        elif b == "fahreauf":
            r = f.rechteck(arg)
            if r is None:
                print("fahreauf %s -> KEIN RECHTECK GEMELDET" % arg)
                error += 1
                continue
            x, y = r[0] + r[2] // 2, r[1] + r[3] // 2
            f.fahre_nahe(x, y)
            print("fahreauf %s -> %d,%d  (rect %d,%d %dx%d)"
                  % (arg, x, y, r[0], r[1], r[2], r[3]))
        elif b == "klicksuche":
            name, px, py = arg.split()[0], *(int(v) for v in arg.split()[1].split(","))
            f.fahre_nahe(px, py)
            time.sleep(0.5)
            r = f.rechteck(name)
            tries = 0
            while r is None and tries < 30:
                step = -3
                if tries == 15:
                    for _ in range(45):
                        f.cmd("mouse_move 0 0 1")
                        time.sleep(0.05)
                for _ in range(abs(step)):
                    f.cmd("mouse_move 0 0 %d" % (1 if step > 0 else -1))
                    time.sleep(0.12)
                time.sleep(0.6)
                r = f.rechteck(name)
                tries += 1
            if r is None:
                print("klicksuche %s -> KEIN RECHTECK GEMELDET" % name)
                error += 1
                continue
            same = 0
            for _settle in range(40):
                time.sleep(0.4)
                r2 = f.rechteck(name)
                if r2 is None:
                    continue
                if tuple(r2) == tuple(r):
                    same += 1
                    if same >= 3:
                        break
                else:
                    same = 0
                    r = r2
            x, y = r[0] + r[2] // 2, r[1] + r[3] // 2
            print("klicksuche %s -> %d,%d  (rect %d,%d %dx%d, %d scrolls)" % (name, x, y, r[0], r[1], r[2], r[3], tries))
            f.klick(x, y, 1)
        elif b in ("klickauf", "doppelauf", "rklickauf", "mklickauf"):
            r = f.rechteck(arg)
            for _try in range(24):
                if r is not None:
                    break
                time.sleep(0.25)
                r = f.rechteck(arg)
            if r is None:
                print("klickauf %s -> KEIN RECHTECK GEMELDET" % arg)
                error += 1
                continue
            x, y = r[0] + r[2] // 2, r[1] + r[3] // 2
            print("klickauf %s -> %d,%d  (rect %d,%d %dx%d)"
                  % (arg, x, y, r[0], r[1], r[2], r[3]))
            if b == "rklickauf":
                f.klick(x, y, 1, key_2=2)
            elif b == "mklickauf":
                f.klick(x, y, 1, key_2=4)
            elif arg == "toast":
                f.klick_nahe(x, y, 1, 1, 0.15)
            else:
                f.klick(x, y, 2 if b == "doppelauf" else 1)
        elif b == "ziehe":
            t = arg.split()
            x0, y0 = (int(v) for v in t[0].split(","))
            x1, y1 = (int(v) for v in t[1].split(","))
            f.ziehe(x0, y0, x1, y1)
            print("ziehe %d,%d -> %d,%d" % (x0, y0, x1, y1))
        elif b == "ziehauf":
            t = arg.split()
            ra, rb = f.rechteck(t[0]), f.rechteck(t[1])
            if ra is None or rb is None:
                print("ziehauf %s -> KEIN RECHTECK GEMELDET" % arg)
                error += 1
                continue
            xa, ya = ra[0] + ra[2] // 2, ra[1] + ra[3] // 2
            xb, yb = rb[0] + rb[2] // 2, rb[1] + rb[3] // 2
            f.ziehe(xa, ya, xb, yb)
            print("ziehauf %s -> %d,%d to %d,%d" % (arg, xa, ya, xb, yb))
        elif b == "ziehnach":
            t = arg.split()
            ra = f.rechteck(t[0])
            if ra is None:
                print("ziehnach %s -> KEIN RECHTECK GEMELDET" % arg)
                error += 1
                continue
            dx, dy = (int(v) for v in t[1].split(","))
            xa, ya = ra[0] + ra[2] // 2, ra[1] + ra[3] // 2
            f.ziehe(xa, ya, xa + dx, ya + dy)
            print("ziehnach %s -> %d,%d by %d,%d" % (t[0], xa, ya, dx, dy))
        elif b == "monitor":
            f.cmd(arg)
            time.sleep(0.5)
            print("monitor %s" % arg)
        elif b == "ziehkante":
            t = arg.split()
            wid = int(t[0])
            edge = t[1]
            dx, dy = (int(v) for v in t[2].split(","))
            g = f.fenstergeom(wid)
            if g is None:
                print("ziehkante %d -> KEINE GEOMETRIE gemeldet" % wid)
                error += 1
                continue
            wx, wy, ww, wh, bo, ti = g
            lx = wx
            rx = wx + ww + 2 * bo - 1
            oy = wy + 1
            uy = wy + ti + wh + bo - 1
            mx = wx + bo + ww // 2
            my = wy + ti + wh // 2
            pos = {"l": (lx, my), "r": (rx, my), "o": (mx, oy),
                      "u": (mx, uy), "lo": (lx, oy), "ro": (rx, oy),
                      "lu": (lx, uy), "ru": (rx, uy)}
            if edge not in pos:
                print("ziehkante: unbekannte Kante %s" % edge)
                error += 1
                continue
            x0, y0 = pos[edge]
            f.ziehe(x0, y0, x0 + dx, y0 + dy)
            print("dragedge id=%d %s from %d,%d by %d,%d "
                  "(fenster %d,%d %dx%d bo=%d ti=%d)"
                  % (wid, edge, x0, y0, dx, dy, wx, wy, ww, wh, bo, ti))
        elif b == "fahrekante":
            t = arg.split()
            wid = int(t[0])
            edge = t[1]
            g = f.fenstergeom(wid)
            if g is None:
                print("fahrekante %d -> KEINE GEOMETRIE gemeldet" % wid)
                error += 1
                continue
            wx, wy, ww, wh, bo, ti = g
            lx = wx
            rx = wx + ww + 2 * bo - 1
            oy = wy + 1
            uy = wy + ti + wh + bo - 1
            mx = wx + bo + ww // 2
            my = wy + ti + wh // 2
            pos = {"l": (lx, my), "r": (rx, my), "o": (mx, oy),
                      "u": (mx, uy), "lo": (lx, oy), "ro": (rx, oy),
                      "lu": (lx, uy), "ru": (rx, uy), "mitte": (mx, my),
                      "titel": (wx + bo + ww // 4, wy + bo + (ti - bo) // 2),
                      "aussen": (wx + ww + 2 * bo + 40 if wx + ww + 2 * bo + 40 < 1800 else max(wx - 40, 2), my)}
            x0, y0 = pos[edge]
            f.fahre(x0, y0)
            print("fahrekante id=%d %s -> %d,%d" % (wid, edge, x0, y0))
        elif b == "kappe":
            t = arg.split()
            if t[0] == "fokus":
                wid = f.fokus_id()
                if wid is None:
                    print("kappe fokus -> KEIN FOKUS gemeldet")
                    error += 1
                    continue
            else:
                wid = int(t[0])
            g = f.fenstergeom(wid)
            if g is None:
                print("kappe %d -> KEINE GEOMETRIE gemeldet" % wid)
                error += 1
                continue
            wx, wy, ww, wh, bo, ti = g
            tx = read_2(f.serial)
            cm = None
            for cm in re.finditer(r" bar=(\d+) capw=(\d+) fr=(\d+)", tx):
                pass
            if cm is None:
                print("cap %d -> NO DIMENSIONS reported" % wid)
                error += 1
                continue
            bar, capw, fr = (int(cm.group(i)) for i in (1, 2, 3))
            n = {"min": 0, "max": 1, "close": 2}[t[1]]
            ow = ww + 2 * fr
            x0 = wx + ow - fr - 3 * capw + n * capw + capw // 2
            y0 = wy + fr + bar // 2
            f.klick(x0, y0)
            print("kappe id=%d %s -> %d,%d" % (wid, t[1], x0, y0))
        elif b == "ziehtitel":
            t = arg.split()
            if t[0] == "fokus":
                wid = f.fokus_id()
                if wid is None:
                    print("ziehtitel fokus -> KEIN FOKUS gemeldet")
                    error += 1
                    continue
            else:
                wid = int(t[0])
            dx, dy = (int(v) for v in t[1].split(","))
            g = f.fenstergeom(wid)
            if g is None:
                print("ziehtitel %d -> KEINE GEOMETRIE gemeldet" % wid)
                error += 1
                continue
            wx, wy, ww, wh, bo, ti = g
            x0 = wx + bo + ww // 2
            y0 = wy + ti // 2
            f.ziehe(x0, y0, x0 + dx, y0 + dy)
            print("dragtitle id=%d from %d,%d by %d,%d "
                  "(fenster %d,%d %dx%d bo=%d ti=%d)"
                  % (wid, x0, y0, dx, dy, wx, wy, ww, wh, bo, ti))
        elif b == "klicknah":
            if "," in arg:
                x, y = (int(v) for v in arg.split(","))
            else:
                r = f.rechteck(arg)
                if r is None:
                    print("klicknah %s -> KEIN RECHTECK GEMELDET" % arg)
                    error += 1
                    continue
                x, y = r[0] + r[2] // 2, r[1] + r[3] // 2
            f.klick_nahe(x, y)
            print("klicknah %s -> %d,%d" % (arg, x, y))
        elif b == "ziehemitte":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("ziehemitte %s -> KEIN RECHTECK GEMELDET" % t[0])
                error += 1
                continue
            dx, dy = (int(v) for v in t[1].split(","))
            x0, y0 = r[0] + r[2] // 2, r[1] + r[3] // 2
            f.ziehe(x0, y0, x0 + dx, y0 + dy)
            print("dragmid %s -> from %d,%d by %d,%d  (rect %d,%d %dx%d)"
                  % (t[0], x0, y0, dx, dy, r[0], r[1], r[2], r[3]))
        elif b == "zieheauf":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("zieheauf %s -> KEIN RECHTECK GEMELDET" % t[0])
                error += 1
                continue
            dx, dy = (int(v) for v in t[1].split(","))
            x0, y0 = r[0] + r[2] - 2, r[1] + r[3] - 2
            f.ziehe(x0, y0, x0 + dx, y0 + dy)
            print("dragopen %s -> from %d,%d by %d,%d  (rect %d,%d %dx%d)"
                  % (t[0], x0, y0, dx, dy, r[0], r[1], r[2], r[3]))
        elif b == "schleppfoto":
            t = arg.split()
            wid = int(t[0])
            if wid < 0:
                ids = re.findall(r"wm: fen i=\d+ id=(\d+) x=\d+ y=\d+ w=\d+ h=\d+ lay=\d+ fl=0 ", read_2(f.serial))
                wid = int(ids[-1]) if ids else 0
            dx, dy = (int(v) for v in t[1].split(","))
            g = f.fenstergeom(wid)
            if g is None:
                print("schleppfoto %d -> NO GEOMETRY reported" % wid)
                error += 1
                continue
            wx, wy, ww, wh, bo, ti = g
            print("schleppfoto: geom %d,%d %dx%d bo=%d ti=%d" % (wx, wy, ww, wh, bo, ti))
            for nm, px, py, ph in f.schleppe_fotos(wx + bo + ww // 3, wy + ti // 2, dx, dy, int(t[2]), t[3]):
                print("schleppfoto: %s %d %d %s" % (nm, px, py, ph))
        elif b == "schleppschnell":
            t = arg.split()
            wid = int(t[0])
            if wid < 0:
                ids = re.findall(r"wm: fen i=\d+ id=(\d+) x=\d+ y=\d+ w=\d+ h=\d+ lay=\d+ fl=0 ", read_2(f.serial))
                wid = int(ids[-1]) if ids else 0
            dx, dy = (int(v) for v in t[1].split(","))
            g = f.fenstergeom(wid)
            if g is None:
                print("schleppschnell %d -> NO GEOMETRY reported" % wid)
                error += 1
                continue
            wx, wy, ww, wh, bo, ti = g
            x0, y0 = wx + bo + ww // 3, wy + ti // 2
            f.fahre(x0, y0)
            time.sleep(0.5)
            f.cmd("mouse_button 1")
            time.sleep(0.4)
            for rep in range(int(t[2])):
                for sgn in (1, -1):
                    ddx, ddy = sgn * dx, sgn * dy
                    while ddx or ddy:
                        sx = max(-120, min(120, ddx))
                        sy = max(-120, min(120, ddy))
                        f.cmd("mouse_move %d %d" % (sx, sy))
                        ddx -= sx
                        ddy -= sy
            f.cmd("mouse_button 0")
            f.x, f.y = x0, y0
            print("schleppschnell: %d,%d x%d done" % (dx, dy, int(t[2])))
        elif b == "ziehfoto":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("ziehfoto %s -> KEIN RECHTECK GEMELDET" % t[0])
                error += 1
                continue
            dx = int(t[1])
            x0 = r[0] + r[2] // 2
            y0 = r[1] + r[3] // 2
            f.ziehe_mit_photo(x0, y0, x0 + dx, y0, t[2] if len(t) > 2 else None)
            print("ziehfoto %s -> %d,%d nach %d,%d  (rect %d,%d %dx%d)"
                  % (t[0], x0, y0, x0 + dx, y0, r[0], r[1], r[2], r[3]))
        elif b == "ziehspurnah":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("ziehspurnah %s -> KEIN RECHTECK GEMELDET" % t[0])
                error += 1
                continue
            p0, p1 = (int(v) for v in t[1].split(","))
            y = r[1] + r[3] // 2
            x0 = r[0] + r[2] * p0 // 100
            x1 = r[0] + r[2] * p1 // 100
            f.ziehe_nahe(x0, y, x1, y)
            print("ziehspurnah %s -> %d,%d nach %d,%d" % (t[0], x0, y, x1, y))
        elif b == "ziehvon":
            t = arg.split()
            r0 = f.rechteck(t[0])
            r1 = f.rechteck(t[1])
            if r0 is None or r1 is None:
                print("ziehvon %s -> KEIN RECHTECK GEMELDET (%s=%s %s=%s)"
                      % (arg, t[0], r0, t[1], r1))
                error += 1
                continue
            x0, y0 = r0[0] + r0[2] // 2, r0[1] + r0[3] // 2
            x1, y1 = r1[0] + r1[2] // 2, r1[1] + r1[3] // 2
            f.ziehe(x0, y0, x1, y1)
            print("ziehvon %s(%d,%d) -> %s(%d,%d)"
                  % (t[0], x0, y0, t[1], x1, y1))
        elif b == "ziehhalt":
            t = arg.split()
            if "," in t[0]:
                x0, y0 = (int(v) for v in t[0].split(","))
            else:
                r0 = f.rechteck(t[0])
                if r0 is None:
                    print("ziehhalt %s -> KEIN RECHTECK GEMELDET" % t[0])
                    error += 1
                    continue
                x0, y0 = r0[0] + r0[2] // 2, r0[1] + r0[3] // 2
            x1, y1 = (int(v) for v in t[1].split(","))
            fo = None
            for extra in t[3:]:
                if extra.startswith("foto="):
                    fo = extra[5:]
            f.ziehe_halt(x0, y0, x1, y1, float(t[2]), photo=fo, esc=("esc" in t[3:]))
            print("ziehhalt (%d,%d) -> (%d,%d) halt %s" % (x0, y0, x1, y1, t[2]))
        elif b == "ziehespur":
            t = arg.split()
            r = f.rechteck(t[0])
            if r is None:
                print("ziehespur %s -> KEIN RECHTECK GEMELDET" % t[0])
                error += 1
                continue
            p0, p1 = (int(v) for v in t[1].split(","))
            y = r[1] + r[3] // 2
            x0 = r[0] + r[2] * p0 // 100
            x1 = r[0] + r[2] * p1 // 100
            f.ziehe(x0, y, x1, y)
            print("ziehespur %s -> %d,%d nach %d,%d  (rect %d,%d %dx%d)"
                  % (t[0], x0, y, x1, y, r[0], r[1], r[2], r[3]))
        elif b == "extern":
            import subprocess
            try:
                rc = subprocess.run(arg, shell=True, timeout=120, capture_output=True, text=True)
                print("extern rc=%d %s" % (rc.returncode, (rc.stdout + rc.stderr).strip()[:200]))
            except subprocess.TimeoutExpired:
                print("extern TIMEOUT: %s" % arg)
                error += 1
        elif b == "taste":
            f.key_2(arg)
        elif b == "tippe":
            names = {" ": "spc", "-": "minus", ".": "dot",
                     ",": "comma", "/": "slash", "_": "shift-minus",
                     ":": "shift-semicolon", ";": "semicolon",
                     "=": "equal", "+": "shift-equal", "?": "shift-slash",
                     "&": "shift-7", "%": "shift-5", "@": "shift-2"}
            if any(arg[i] == arg[i + 1] for i in range(len(arg) - 1)):
                tippe_gap = max(tippe_gap, 0.4)
            for ch in arg:
                f.key_2(names.get(ch, "shift-" + ch.lower() if ch.isalpha() and ch.isupper() else ch))
                time.sleep(tippe_gap)
            tippe_gap = base_gap
            print("tippe %s (%d Zeichen)" % (arg, len(arg)))
        elif b == "schritt":
            with open(os.path.join(out, "schritte.tsv"), "a", encoding="utf-8") as sf:
                sf.write("%d\t%.1f\t%s\n" % (len(read_2(f.serial)), time.time(), arg))
        elif b == "foto":
            if not f.photo(arg):
                error += 1
        elif b == "serie":
            sp = arg.split()
            sm, sn, snm = sp[0], sp[1], sp[2]
            if not f.serie(sm, int(sn), snm, pace_ms=int(sp[3]) if len(sp) > 3 else 0):
                error += 1
        else:
            print("unbekannter Befehl: %s" % z)
            error += 1
    print("drehbuch fertig, fehler=%d" % error)
    return 0


if __name__ == "__main__":
    sys.exit(main())
