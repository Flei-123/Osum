#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""hoverprobe.py -- DEN ZEIGER WIRKLICH UEBER EINE KACHEL STELLEN UND
ES FOTOGRAFIEREN.

    python3 hoverprobe.py [name] [breite] [hoehe]

============================================================ DIE LAGE
Die Vorrunde konnte den Hover nur im QUELLTEXT nachweisen. Ihr Aufbau
schickte `mouse_move` in einen Monitor, hinter dem GAR KEIN
Zeigegeraet haengt, das der Kern abfragt:

    qemu ... -device VGA,edid=on,...      <- kein usb-tablet, kein usb-kbd

Der Kern zaehlte `kl=1` bei `xy=639,222`, aber `qs` meldete nie
`qs: druck`. Das ist KEIN Fehler des Kontrollzentrums, sondern der
Messung: ohne `-device qemu-xhci -device usb-tablet` kommt bei diesem
Kern kein einziges Mausereignis an, denn `kernel/usb.fi` hat genau
einen Wirtstreiber (xHCI), und das ist der Weg, ueber den `ps2m.fi`
seine Pakete bekommt (`gfx.fi:232 -> ps2m.usb_packet`).

`pruef/start.sh` haengt beides an -- deshalb baut diese Probe auf
start.sh auf und nicht auf einem eigenen qemu-Aufruf.

====================================================== DER ZWEITE FUND
EINE BEWEGUNG IST NICHT EIN KLICK, und `klick.py` kann nur klicken.
Hover braucht `EV_MOVE`, und `wm.fi:7085` schickt das nur, wenn sich
der Zeiger BEWEGT und dabei INNERHALB des Fensters steht:

    if lokal_x >= 0 && lokal_y >= 0 {
        ev_push(state, i, E_MOVE, lokal_x, lokal_y, btn)
    }

`klick.py::gehe()` faehrt zwar dorthin -- aber es faehrt IMMER zuerst
mit zwoelf Spruengen `mouse_move -200 -200` in die Ecke. Auf dem
TABLET (absolut) ist `mouse_move -200 -200` kein Schritt, sondern der
Ort (-200,-200), also der Anschlag (0,0); die zwoelf Spruenge sind
also harmlos, aber die anschliessende Fahrt besteht aus
EINZELSPRUENGEN, nach denen der Zeiger jeweils SOFORT am naechsten Ort
steht. Der letzte Sprung landet auf dem Ziel -- und danach bewegt sich
nichts mehr. Der Hover-Zustand entsteht damit zwar, aber `klick.py`
klickt unmittelbar danach, und der Klick SCHALTET DIE KACHEL UM. Wer
danach fotografiert, sieht den neuen Zustand und nicht den Hover.

Diese Probe macht deshalb dreierlei anders:

  1. sie FAEHRT NUR und klickt nicht,
  2. sie faehrt in mehreren KLEINEN Schritten auf das Ziel zu, damit
     mindestens eine Bewegung INNERHALB des Fensters liegt (eine
     einzige Bewegung von ausserhalb nach innen erzeugt genau ein
     EV_MOVE -- das genuegt zwar, aber mehrere sind robuster gegen
     einen verschluckten Bericht),
  3. sie wartet danach, bis `qs` den Neuanstrich wirklich gemacht hat,
     und fotografiert ERST DANN.

===================================================== WAS SIE AUSGIBT
Fuer jeden Prueffall ein PNG und die gemessene Farbe der Kachelflaeche,
dazu die Farbe einer NACHBARKACHEL ohne Zeiger im selben Bild. Der
Vergleich steht damit im selben Foto und nicht zwischen zwei Laeufen.
"""
import json
import os
import re
import socket
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)

NAME = sys.argv[1] if len(sys.argv) > 1 else "hp"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
SKALA = os.environ.get("UISCALE", "1")
THEMA = os.environ.get("THEMA", "")

D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
SER = os.path.join(D, "serial.txt")
MON = os.path.join(D, "mon.sock")


def s():
    try:
        return open(SER, "rb").read().replace(b"\x00", b"").decode(
            "utf-8", "replace")
    except OSError:
        return ""


class Monitor:
    """Nur das, was diese Probe braucht: fahren, Tasten, Foto."""

    def __init__(self, pfad, frist=40.0):
        bis = time.time() + frist
        self.s = None
        while time.time() < bis:
            try:
                k = socket.socket(socket.AF_UNIX)
                k.settimeout(5.0)
                k.connect(pfad)
                self.s = k
                time.sleep(0.3)
                self._leer()
                return
            except OSError:
                time.sleep(0.2)
        raise RuntimeError("kein Monitor an %s" % pfad)

    def _leer(self):
        try:
            self.s.recv(1 << 16)
        except OSError:
            pass

    def sag(self, zeile, pause=0.08):
        self.s.sendall((zeile + "\n").encode())
        time.sleep(pause)
        self._leer()

    def taste(self, t, pause=1.0):
        self.sag("sendkey %s" % t, pause)

    def foto(self, pfad):
        """screendump schreibt PPM; PNG daraus und das PPM SOFORT weg
        (die Platte ist eng: ein 1280x800-PPM sind 3 MB)."""
        ppm = pfad + ".ppm"
        self.sag("screendump %s" % ppm, 0.2)
        bis = time.time() + 25
        while time.time() < bis:
            if os.path.exists(ppm) and os.path.getsize(ppm) > 1000:
                a = os.path.getsize(ppm)
                time.sleep(0.4)
                if os.path.getsize(ppm) == a:
                    break
            time.sleep(0.3)
        from PIL import Image
        Image.open(ppm).convert("RGB").save(pfad)
        os.unlink(ppm)
        return pfad

    # ------------------------------------------------------------ Maus
    #
    # RELATIV, denn dieser Aufbau faehrt `-device usb-mouse`. Warum
    # nicht das Tablet: siehe den Block in pruef/start.sh -- dieser
    # Kern liest das BOOT-PROTOKOLL (ein Oktett je Achse, mit
    # Vorzeichen, also ein SCHRITT), und die absolute Lage eines
    # Tablets ergibt darin Unsinn. Gemessen war `bew=0` bei `pk=178`.
    def ecke(self):
        """In die linke obere Ecke -- der Anschlag loescht die
        Vorgeschichte. Ein PS/2-Schritt traegt neun Bit je Achse, also
        viele kleine Spruenge statt eines grossen."""
        for _ in range(14):
            self.sag("mouse_move -120 -120", 0.02)
        self.x = 0
        self.y = 0
        time.sleep(0.3)

    def fahre_auf(self, x, y, schritte=10):
        """AUF einen Ort zufahren -- in vielen kleinen Schritten.

        Der Zeiger MUSS sich bewegen, sonst gibt es kein E_MOVE:
        `wm.fi` schickt das Ereignis nur, wenn sich die Lage aendert
        UND sie im Fenster liegt. Ein einziger Sprung von aussen nach
        innen erzeugt genau ein Ereignis; viele kleine erzeugen viele,
        und das ist gegen einen verschluckten Bericht robuster.
        """
        self.ecke()
        gx = gy = 0
        for k in range(1, schritte + 1):
            zx = int(round(x * k / schritte))
            zy = int(round(y * k / schritte))
            dx, dy = zx - gx, zy - gy
            while dx or dy:
                sx = max(-100, min(100, dx))
                sy = max(-100, min(100, dy))
                self.sag("mouse_move %d %d" % (sx, sy), 0.05)
                dx -= sx
                dy -= sy
            gx, gy = zx, zy
        # Zwei Wackler DIREKT auf dem Ziel: hin und zurueck um einen
        # Bildpunkt. Damit liegt garantiert eine Bewegung INNERHALB des
        # Fensters, auch wenn der letzte Schritt von aussen hereinkam.
        self.sag("mouse_move 1 0", 0.08)
        self.sag("mouse_move -1 0", 0.08)
        self.x, self.y = x, y
        time.sleep(0.8)


def farbe(bild, x, y, r=3):
    """Mittlere Farbe eines kleinen Quadrats -- ein einzelner Punkt
    kann auf einem Rand oder einer Schrift liegen."""
    from PIL import Image
    b = Image.open(bild).convert("RGB")
    # Ausserhalb des Bildes ist KEINE Farbe, sondern ein Fehler in der
    # Rechnung des Aufrufers -- und der soll ihn sehen.
    if not (0 <= x < b.width and 0 <= y < b.height):
        raise ValueError("Messpunkt (%d,%d) liegt ausserhalb %dx%d"
                         % (x, y, b.width, b.height))
    sx = sy = sz = n = 0
    for yy in range(max(0, y - r), min(b.height, y + r + 1)):
        for xx in range(max(0, x - r), min(b.width, x + r + 1)):
            p = b.getpixel((xx, yy))
            sx += p[0]
            sy += p[1]
            sz += p[2]
            n += 1
    return (sx // n, sy // n, sz // n)


def hexf(c):
    return "#%02X%02X%02X" % c


def abstand(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))


def kacheln():
    """Die Kachelrechtecke, die `qs` selbst auf die Leitung schreibt:
    `qs: krect t=.. pl=.. x=.. y=.. w=.. h=.. an=..`"""
    aus = {}
    for m in re.finditer(
            r"qs: kachel n=(\d+) platz=(\d+) x=(\d+) y=(\d+) w=(\d+) "
            r"h=(\d+) an=(\d+)", s()):
        pl = int(m.group(2))
        aus[pl] = {
            "t": int(m.group(1)), "pl": pl,
            "x": int(m.group(3)), "y": int(m.group(4)),
            "w": int(m.group(5)), "h": int(m.group(6)),
            "an": int(m.group(7)) == 1,
        }
    return aus


def fenster_qs():
    """Wo steht das qs-Fenster? `wm: fen i=.. id=.. x=.. y=.. w=.. h=..`
    Die Kachelkoordinaten sind FENSTERLOKAL, das Foto ist global."""
    letzt = {}
    for m in re.finditer(
            r"wm: fen i=\d+ id=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)",
            s()):
        letzt[int(m.group(1))] = (int(m.group(2)), int(m.group(3)),
                                  int(m.group(4)), int(m.group(5)))
    return letzt


def qs_id():
    v = re.findall(r"qs: win id=(\d+)", s())
    return int(v[-1]) if v else None


def main():
    os.makedirs(SHOTS, exist_ok=True)
    extra = "uiscale=%s %s" % (SKALA, THEMA)
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE), extra],
                   check=True, capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 240:
        # WORAUF GEWARTET WIRD -- und warum NICHT auf
        # "taskbar: start x=". Dieser Kern schreibt diese Zeile
        # NICHT: gemessen an Lauf hp1 null Treffer in 16 kB
        # Mitschnitt, waehrend `wm: fen` die Leiste bei y=760
        # laengst fuehrte. Wer darauf wartet, wartet fuer immer --
        # genau daran ist der erste Anlauf dieser Runde
        # haengengeblieben. Was dieser Aufbau WIRKLICH schreibt,
        # sobald der Schreibtisch steht, ist der Fensterbericht des
        # Servers; die Leiste steht darin als eigenes Fenster mit
        # `lay=2`.
        if len(re.findall(r"wm: fen i=\d+ id=\d+ .*lay=2", s())) >= 3:
            break
        time.sleep(0.3)
    else:
        print("KEIN SCHREIBTISCH -- Abbruch")
        return 2
    print("hochgefahren nach %.1f s" % (time.time() - t0), flush=True)

    m = Monitor(MON)
    befund = {"name": NAME, "skala": SKALA, "thema": THEMA,
              "breite": BREITE, "hoehe": HOEHE, "faelle": []}

    # ============================ DAS KONTROLLZENTRUM IST SCHON OFFEN
    #
    # DER FUND, DER DEN ERSTEN ANLAUF GEKOSTET HAT. `qs` meldet
    # `qs: win id=10` schon WAEHREND DES STARTS -- das Panel steht von
    # sich aus da. Und Super+A ist ein UMSCHALTER
    # (`kernel/user/qs.fi::step`, `if open_ != 0 { shut } else
    # { open_at }`). Wer also blind viermal Super+A drueckt, um es
    # "aufzumachen", macht es zweimal zu und zweimal auf und weiss am
    # Ende nicht, was er hat.
    #
    # Wichtiger noch: `kacheln_say()` -- die Zeilen `qs: kachel n=..
    # platz=.. x=..`, aus denen diese Probe ihre Zielkoordinaten holt
    # -- steht IN `open_at()` und sonst nirgends. Ein Panel, das beim
    # Start von selbst aufging, hat sie nie geschrieben. Deshalb sah
    # der erste Anlauf "KEINE Kachelrechtecke auf der Leitung", obwohl
    # das Panel im Bild stand.
    #
    # Der Weg ist deshalb: ZUERST sicher SCHLIESSEN (Escape, das `qs`
    # selbst als `shut` behandelt), pruefen dass es zu ist, und DANN
    # genau EINMAL Super+A -- das ist ein echtes `open_at`, und damit
    # kommt der Kachelbericht.
    m.taste("esc", 2.0)
    n_shut = s().count("qs: closed")
    n_kach = len(kacheln())
    for versuch in range(5):
        m.taste("meta_l-a", 3.5)
        if len(kacheln()) > n_kach:
            break
        # kam kein Bericht, war das ein Zumachen -- noch einmal.
        time.sleep(1.0)
    else:
        print("KEIN open_at trotz 5x Super+A -- Abbruch")
        return 2
    # WELCHES FENSTER IST DAS PANEL -- mit Rueckfall.
    #
    # `qs: win id=` kommt genau EINMAL, und eine Zeile, die einmal
    # vorkommt, ist eine Hoffnung: im dunklen Lauf stand sie zerrissen
    # da (`qs: geo x=889 y=462 w=387 h=elf2:9 4s`), obwohl vier
    # Kachelzeilen und ein vollstaendiger `qs: geo` vorlagen. Die Probe
    # brach mit "ging nicht auf" ab, obwohl das Panel offen war.
    #
    # Also zweiter Weg: `qs: geo x= y= w= h=` sagt, WO das Panel steht.
    # Dasselbe Rechteck im Fensterbericht des Servers ist das Fenster.
    fen = None
    wid = qs_id()
    if wid is not None:
        fen = fenster_qs().get(wid)
    if fen is None:
        geo = re.findall(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)", s())
        if geo:
            gx, gy, gw, gh = (int(v) for v in geo[-1])
            for i, r in fenster_qs().items():
                if r == (gx, gy, gw, gh):
                    wid, fen = i, r
                    print("qs-Fenster ueber qs:geo gefunden (id=%d)" % i,
                          flush=True)
                    break
    if fen is None:
        print("KEIN Rechteck fuer das qs-Fenster -- Abbruch")
        return 2
    fx, fy, fw, fh = fen
    print("qs-Fenster id=%d bei (%d,%d) %dx%d" % (wid, fx, fy, fw, fh),
          flush=True)

    k = kacheln()
    if not k:
        print("KEINE Kachelrechtecke auf der Leitung -- Abbruch")
        return 2
    # eine AUSGESCHALTETE und eine EINGESCHALTETE Kachel suchen, und
    # dazu je eine NACHBARKACHEL im gleichen Zustand als Vergleich.
    aus = [v for v in k.values() if not v["an"]]
    ein = [v for v in k.values() if v["an"]]
    print("Kacheln: %d aus, %d ein" % (len(aus), len(ein)), flush=True)
    befund["kacheln"] = list(k.values())

    def mitte(r):
        return (fx + r["x"] + r["w"] // 2, fy + r["y"] + r["h"] // 2)

    def paar(liste, was):
        """Eine Kachel bekommt den Zeiger, eine zweite ist die
        Vergleichsflaeche IM SELBEN BILD.

        AM LIEBSTEN ZWEI GLEICHEN ZUSTANDS -- dann misst der Vergleich
        wirklich nur den Zeiger. Gibt es davon nur EINE (im dunklen
        Lauf war genau eine Kachel aus), wird trotzdem gemessen und
        irgendeine andere als Nachbar genommen: der Wert
        `d_ohne_hover` -- derselbe Knopf ohne und mit Zeiger -- ist
        ohnehin die Zahl, auf die es ankommt, und der wird nicht
        schlechter. Ein uebersprungener Fall waere dagegen eine
        Messluecke, und genau die hat in der Vorrunde gefehlt.
        """
        if len(liste) >= 2:
            return liste[0], liste[1]
        if len(liste) == 1:
            andere = [v for v in k.values() if v["pl"] != liste[0]["pl"]]
            if andere:
                return liste[0], andere[0]
        return None

    def messe(ziel, nachbar, marke):
        zx, zy = mitte(ziel)
        nx, ny = mitte(nachbar)
        # 1. Zeiger in die ECKE -> Bild ohne Hover
        m.ecke()
        time.sleep(1.2)
        b0 = m.foto(os.path.join(SHOTS, "%s-ohne.png" % marke))
        # 2. Zeiger AUF die Kachel -> Bild mit Hover
        m.fahre_auf(zx, zy)
        time.sleep(1.2)
        b1 = m.foto(os.path.join(SHOTS, "%s-hover.png" % marke))
        # WO GEMESSEN WIRD -- und warum nicht in der Mitte.
        #
        # Eine Kachel traegt ein Symbol und zwei Textzeilen. Auf halber
        # Hoehe liegt das Symbol: gemessen wurde dort #AFB4BC, waehrend
        # das Panel ausweislich seiner eigenen Meldung `bg=15857145`
        # (#F1F5F9) gemalt hatte. Das ist die Zeichnung und nicht die
        # Flaeche.
        #
        # Frei ist der Streifen GANZ OBEN zwischen Oberkante und
        # Symbol. Sechs Punkte unter der Oberkante liegen sicher
        # innerhalb der Kachel (auch bei rundem Eck) und ueber allem,
        # was hineingemalt wird. Und NEBEN der Mitte, damit der
        # Mauszeiger selbst nicht ins Messquadrat faellt.
        mx = zx - ziel["w"] // 3
        my = fy + ziel["y"] + ziel.get("oben", 6)
        c_ohne = farbe(b0, mx, my)
        c_hov = farbe(b1, mx, my)
        c_nach = farbe(b1, nx - nachbar["w"] // 3,
                       fy + nachbar["y"] + nachbar.get("oben", 6))
        e = {"marke": marke, "kachel_pl": ziel["pl"], "an": ziel["an"],
             "nachbar_pl": nachbar["pl"],
             "mess_xy": [mx, my], "zeiger_xy": [zx, zy],
             "ohne": c_ohne, "hover": c_hov, "nachbar": c_nach,
             "d_ohne_hover": abstand(c_ohne, c_hov),
             "d_hover_nachbar": abstand(c_hov, c_nach),
             "bild_ohne": b0, "bild_hover": b1}
        befund["faelle"].append(e)
        print("%-12s an=%d  ohne %s  hover %s  nachbar %s   d=%d/%d"
              % (marke, 1 if ziel["an"] else 0, hexf(c_ohne), hexf(c_hov),
                 hexf(c_nach), e["d_ohne_hover"], e["d_hover_nachbar"]),
              flush=True)
        return e

    p = paar(aus, "aus")
    if p:
        messe(p[0], p[1], "kachel-aus")
    p = paar(ein, "ein")
    if p:
        messe(p[0], p[1], "kachel-ein")

    # ------------------------------------------------ Fussknoepfe
    fb = {}
    # NACHSICHTIG LESEN -- die Leitung verliert Zeichen. Gemessen in
    # hp5: `qs: fussb n=1 x=1234 y=714  /32 h=32 z=0`, aus `w=32` wurde
    # `/32`. Ein starres Muster findet die Zeile dann nicht, und die
    # Probe meldet "keine Rechtecke", obwohl zwei dastehen. Verlangt
    # werden deshalb nur n, x und y; w/h bekommen die bekannte
    # Knopfgroesse als Rueckfall.
    for mm in re.finditer(r"qs: fussb n=(\d+) x=(\d+) y=(\d+)(.*)", s()):
        rest = mm.group(4)
        gw = re.search(r"w=(\d+)", rest)
        gh = re.search(r"h=(\d+)", rest)
        gz = re.search(r"z=(\d+)", rest)
        fb[mm.group(1)] = {
            "x": int(mm.group(2)), "y": int(mm.group(3)),
            "w": int(gw.group(1)) if gw else 32,
            "h": int(gh.group(1)) if gh else 32,
            "z": int(gz.group(1)) if gz else -1}
    befund["fuss"] = fb
    namen = list(fb.keys())
    if len(namen) >= 2:
        # DIE FUSSKNOEPFE MELDEN SCHON GLOBAL. `qs.fi` addiert `px_`/
        # `py_` (die Fensterecke) vor dem Bericht dazu -- die Kacheln
        # dagegen melden FENSTERLOKAL. Wer beide gleich behandelt,
        # rechnet die Fensterecke zweimal drauf und misst ausserhalb
        # des Bildes; genau daran ist der Lauf hp1 mit einer Division
        # durch null gestorben.
        a = fb[namen[0]]
        b = fb[namen[1]]
        messe({"pl": 900, "an": False, "x": a["x"] - fx, "y": a["y"] - fy,
               "w": a["w"], "h": a["h"], "oben": 4},
              {"pl": 901, "an": False, "x": b["x"] - fx, "y": b["y"] - fy,
               "w": b["w"], "h": b["h"], "oben": 4}, "fuss-%s" % namen[0])
    else:
        print("Fussknoepfe: keine qs-Rechtecke auf der Leitung (%d)"
              % len(namen), flush=True)

    # ================================================ DER SCHIEBEREGLER
    #
    # Der Regler meldet seine Rinne selbst:
    #   qs: hell spur von=929 bis=1266 ym=656   (BILDSCHIRMPUNKTE)
    # Das ist schon global, wie bei den Fussknoepfen -- also wird die
    # Fensterecke hier NICHT noch einmal addiert.
    #
    # WAS HIER GEPRUEFT WIRD, und was ausdruecklich nicht: ob der
    # Zeiger UEBER dem Regler eine sichtbare Aenderung erzeugt. Der
    # Regler hat in diesem Panel KEINEN eigenen Hover-Zustand -- er
    # hat einen Wert, und der aendert sich erst beim Ziehen. Ein
    # Unterschied von 0 ist hier deshalb kein Fehler, sondern der
    # Befund; er wird als solcher gemeldet und nicht als "kaputt".
    sp = re.findall(r"qs: hell spur von=(\d+) bis=(\d+) ym=(\d+)", s())
    if sp:
        v, bis, ym = (int(x) for x in sp[-1])
        mitte = (v + bis) // 2
        m.ecke()
        time.sleep(1.0)
        b0 = m.foto(os.path.join(SHOTS, "regler-ohne.png"))
        m.fahre_auf(mitte, ym)
        time.sleep(1.0)
        b1 = m.foto(os.path.join(SHOTS, "regler-hover.png"))
        # ueber der Rinne messen, nicht IN ihr: die Rinne selbst ist
        # zweifarbig (gefuellt bis zum Wert, leer danach).
        c0 = farbe(b0, mitte, ym - 10)
        c1 = farbe(b1, mitte, ym - 10)
        e = {"marke": "regler", "kachel_pl": -1, "an": False,
             "nachbar_pl": -1, "mess_xy": [mitte, ym - 10],
             "zeiger_xy": [mitte, ym], "ohne": list(c0),
             "hover": list(c1), "nachbar": list(c0),
             "d_ohne_hover": abstand(c0, c1), "d_hover_nachbar": 0,
             "bild_ohne": b0, "bild_hover": b1,
             "hinweis": "der Regler hat keinen eigenen Hover-Zustand"}
        befund["faelle"].append(e)
        print("%-12s rinne %d..%d ym=%d  ohne %s  hover %s   d=%d"
              % ("regler", v, bis, ym, hexf(c0), hexf(c1),
                 e["d_ohne_hover"]), flush=True)
    else:
        print("Regler: keine Rinne auf der Leitung", flush=True)

    # ------------------------------------------------------ Schluss
    with open(os.path.join(D, "befund.json"), "w") as f:
        json.dump(befund, f, indent=1)
    roh = s()
    open(os.path.join(D, "serial-kopie.txt"), "w").write(roh[-200000:])
    print("\nBefund: %s" % os.path.join(D, "befund.json"))
    print("Bilder: %s" % SHOTS)
    for z in re.findall(r"^qs: .*$", roh, re.M)[-12:]:
        print("   ", z)
    try:
        pid = int(open(os.path.join(D, "pid")).read().strip())
        os.kill(pid, 15)
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
