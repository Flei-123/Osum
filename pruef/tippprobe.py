#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tippprobe.py -- WARUM STEHT DER GETIPPTE TEXT NUR ZU 77 % IM BILD?

    python3 tippprobe.py [name] [breite] [hoehe]

WAS BISHER GEMESSEN IST:
  * Die Tasten kommen an: 22 `key:`-Zeilen, und sie ergeben Zeichen fuer
    Zeichen `echo Gruesse` -- kein Zeichen fehlt, keines doppelt. Ein
    Problem mit Wiederholung, Loslassen oder AltGr ist es also nicht.
  * Im Foto steht der Text trotzdem nur zu 77 % (Schwelle 97 %).

DER VERDACHT, und diese Probe entscheidet ihn. Im Foto liegt ueber dem
ganzen Schirm gruener Text -- gemessen von x=4 bis x=764 und y=40 bis
y=632, waehrend das Terminalfenster nur x=24..584, y=40..420 gross ist.
Die Glyphen darin sind ein VERDOPPELTES 8x16-Bitmuster (jeder Bildpunkt
2x2, Zellbreite 16, Zeilenabstand 32) -- also NICHT die TTF-Schrift, mit
der der Fensterserver seine Zellen malt.

Das passt auf genau eine Stelle im Kern: `kgui.kopf_malen` schreibt die
Pulszeile MIT DER EINGEBAUTEN 8x16-SCHRIFT direkt in den Rahmenpuffer,
an `compose` vorbei (Kommentar dort: "Diese Zeile haengt an nichts: kein
Fenster, kein Puffer, keine TTF-Schrift").

Diese Probe misst denselben Satz zweimal:
  A  wie bisher              -- der Kopf malt mit
  B  mit `nopuls` ... und wenn das nicht reicht, wird der Text NICHT im
     Vollbild gesucht, sondern NUR im Rechteck des Terminalfensters.

Der Vergleich beantwortet die Frage sauber: liegt es am System (dann ist
der Text auch im Fensterausschnitt schlecht) oder an der Messung (dann
ist er dort sauber und nur das Vollbild ist verdeckt).
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HIER, ".."))
sys.path.insert(0, HIER)
from klick import Maschine

NAME = sys.argv[1] if len(sys.argv) > 1 else "tp"
BREITE = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
HOEHE = int(sys.argv[3]) if len(sys.argv) > 3 else 800
D = os.path.join(HIER, "laeufe", NAME)
SHOTS = os.path.join(HIER, "shots", NAME)
os.makedirs(SHOTS, exist_ok=True)
SER = os.path.join(D, "serial.txt")
WORT = "Gruesse"


def s():
    try:
        return open(SER, "rb").read().replace(b"\x00", b"").decode(
            "utf-8", "replace")
    except OSError:
        return ""


def fenster():
    aus = {}
    for m in re.finditer(r"wm: fen i=\d+ id=(\d+) x=(\d+) y=(\d+) w=(\d+) "
                         r"h=(\d+) lay=(\d+) fl=(\d+)", s()):
        aus[int(m.group(1))] = tuple(int(m.group(k)) for k in range(2, 8))
    return aus


def suche(bild, text, ttf, px, kasten=None):
    """searchtext.py auf dem ganzen Bild -- oder nur auf einem Ausschnitt."""
    from PIL import Image
    im = Image.open(bild).convert("RGB")
    if kasten:
        im = im.crop(kasten)
    ppm = "/tmp/tipp-%d.ppm" % os.getpid()
    im.save(ppm)
    try:
        r = subprocess.run(
            ["python3", os.path.join(REPO, "tools", "usbimg", "searchtext.py"),
             ppm, os.path.join(REPO, "assets", ttf), str(px), text],
            capture_output=True, text=True, timeout=300)
        m = re.search(r"(\d+)% der \d+ Tintenpunkte", r.stdout)
        if m:
            return int(m.group(1))
        m = re.search(r"bester Wert (\d+)%", r.stdout)
        return int(m.group(1)) if m else None
    finally:
        if os.path.exists(ppm):
            os.unlink(ppm)


def main():
    subprocess.run(["bash", os.path.join(HIER, "start.sh"), NAME,
                    str(BREITE), str(HOEHE)], check=True,
                   capture_output=True, text=True, timeout=60)
    t0 = time.time()
    while time.time() - t0 < 180:
        if "taskbar: start x=" in s():
            break
        time.sleep(0.3)
    print("hochgefahren nach %.1f s" % (time.time() - t0), flush=True)
    bis = time.time() + 120
    while time.time() < bis and not fenster():
        time.sleep(0.5)

    m = Maschine(os.path.join(D, "mon.sock"), BREITE, HOEHE)
    f = fenster()
    term = None
    for wid, (x, y, w, h, lay, fl) in f.items():
        if lay == 1 and (fl & 3) == 0 and w >= 200:
            term = (wid, x, y, w, h)
    if not term:
        print("kein Terminalfenster:", f)
        return 1
    wid, x, y, w, h = term
    print("Terminalfenster id=%d x=%d y=%d w=%d h=%d" % (wid, x, y, w, h),
          flush=True)

    vor = len(re.findall(r"key: ", s()))
    m.klick_auf(x + w // 2, y + h // 2)
    time.sleep(1.0)
    m.tippe("echo " + WORT)
    m.taste("ret")
    time.sleep(3.0)
    nach = len(re.findall(r"key: ", s()))
    zeichen = re.findall(r"key: (.)", s())[-len(WORT) - 6:]
    print("key:-Zeilen %d -> %d, zuletzt: %s"
          % (vor, nach, "".join(zeichen)), flush=True)

    bild = os.path.join(SHOTS, "getippt.png")
    m.foto(bild)

    # Der INNENbereich des Fensters: Rahmen 2, Titelleiste 22.
    innen = (x + 2, y + 22, x + 2 + w, y + 22 + h)
    print("\n%-34s %s" % ("Suche", "Treffer"))
    for titel, ttf, px, kasten in (
            ("Vollbild, sans 15", "osum-sans.ttf", 15, None),
            ("Vollbild, mono 16", "osum-mono.ttf", 16, None),
            ("nur Fensterinneres, mono 16", "osum-mono.ttf", 16, innen),
            ("nur Fensterinneres, mono 15", "osum-mono.ttf", 15, innen),
            ("nur Fensterinneres, sans 15", "osum-sans.ttf", 15, innen)):
        v = suche(bild, WORT, ttf, px, kasten)
        print("%-34s %s%%" % (titel, v), flush=True)

    # Und die Gegenprobe: liegt ueberhaupt gruene Tinte AUSSERHALB des
    # Fensters? Dann malt der Kopf ueber den Schreibtisch.
    from PIL import Image
    im = Image.open(bild).convert("RGB")
    px_ = im.load()
    G = (0, 255, 102)
    aussen = sum(1 for yy in range(0, HOEHE, 2) for xx in range(0, BREITE, 2)
                 if px_[xx, yy] == G
                 and not (innen[0] <= xx < innen[2] and innen[1] <= yy < innen[3]))
    drin = sum(1 for yy in range(innen[1], innen[3], 2)
               for xx in range(innen[0], innen[2], 2) if px_[xx, yy] == G)
    print("\ngruene Punkte im Fenster: %d   AUSSERHALB: %d" % (drin, aussen))
    print("(ausserhalb > 0 heisst: der Puls-Kopf malt ueber den Schirm)")

    m.sag("quit", 0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
