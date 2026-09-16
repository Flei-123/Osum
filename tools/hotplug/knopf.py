#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/hotplug/knopf.py -- DER AUSWURFKNOPF, GEDRUECKT UND FOTOGRAFIERT.

    python3 tools/hotplug/knopf.py <arbeitsverzeichnis> <ausgabeverzeichnis>

Die Vorrunde hat den Knopf GEBAUT, aber nie im Bild gehabt: "der
Dateimanager startet in diesem Baum nicht bis zum Fenster". Das stimmt
seit dieser Runde nicht mehr (der /data-Baum von `tools/k15/tree.py`
reicht, siehe `bilder.sh`), und deshalb wird hier zu Ende gefahren, was
dort offenblieb:

    10-ohne.png     die Seitenleiste, bevor der Stick da ist
    20-steckt.png   der Stick STEHT IN DER LEISTE -- ohne Zutun, weil
                    der Dateimanager seit dieser Runde am Systembus
                    haengt (kein F5, kein Klick auf "Aktualisieren")
    30-ausgeworfen.png  nach dem Klick auf den Auswurfknopf

DREI REGELN, DIE JEDE FRUEHERE RUNDE SCHON EINMAL GEKOSTET HABEN:

1. GEKLICKT WIRD AUF GEMELDETE KOORDINATEN, nicht auf geratene. Der
   Dateimanager meldet jedes Bedienelement als
       explorer: rect id=<n> kind=<k> x=<x> y=<y> w=<w> h=<h>
   -- aber NUR, wenn `/etc/uitrace` auf der Platte liegt (`dbg_setup`).
   Ohne die Datei schweigt er, und dann klickt man ins Blaue.
   Die Lage des FENSTERS kommt aus `wm: win ... x= y=`; die Rechtecke
   sind fensterrelativ.

2. DIE MAUS IST RELATIV. QEMUs `mouse_move` ueber den Monitor schickt
   Schritte, keine Orte -- deshalb wird ueber die linke obere Ecke
   gefahren und von dort gezaehlt. Das steht ausgeschrieben in
   `pruef/klick.py`, und genau diese Datei wird hier benutzt statt
   einer zweiten Rechnung daneben.

3. DER KNOPF SAGT AUCH NEIN. Ist auf dem Stick noch etwas offen,
   antwortet der Kern mit E_BUSY, und die Statuszeile sagt das. Dieser
   Lauf haelt nichts offen -- gemessen wird der Weg, der gutgeht.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(os.path.dirname(HIER))
sys.path.insert(0, os.path.join(WURZEL, "pruef"))
from klick import Maschine  # noqa: E402

ARB = sys.argv[1]
AUS = sys.argv[2]
BREIT, HOCH = 1024, 768
SER = os.path.join(ARB, "knopf-seriell.txt")
SOCK = os.path.join(ARB, "knopf.sock")
os.makedirs(AUS, exist_ok=True)
for f in (SER, SOCK):
    if os.path.exists(f):
        os.unlink(f)

befund = []


def sag(*a):
    t = " ".join(str(x) for x in a)
    print("  " + t, flush=True)
    befund.append(t)


def lies():
    try:
        return open(SER, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def warte_auf(muster, grenze=120.0, was=""):
    t0 = time.time()
    while time.time() - t0 < grenze:
        if re.search(muster, lies()):
            sag("gesehen: %s (%.0fs)" % (was or muster, time.time() - t0))
            return True
        if p.poll() is not None:
            sag("QEMU ist vorzeitig weg, rc=%s" % p.returncode)
            return False
        time.sleep(0.5)
    sag("NICHT gesehen: %s" % (was or muster))
    return False


# ------------------------------------------------------------ der Lauf
# DIE SCHREIBTISCHSCHLEIFE, NICHT DIE HALTESCHLEIFE.
#
# `wmhold`/`wighalt` haelt das Bild still -- und ruft NIE `usb.poll`.
# Gemessen: `mouse: id=3 packets=0`, kein einziger Klick kam an, obwohl
# die Maus aufgezaehlt war (`driver=mouse`). Die Vorrunde hat deshalb
# nie geklickt, sondern der Shell ein Skript gereicht.
#
# `wmdauer` laeuft `wait_wm` dauerhaft, und DORT stehen `usb.poll`,
# `usb.hotplug_work` und `wechsel_schritt` hintereinander -- dieselbe
# Schleife, in der ein Mensch den Stick steckt und klickt.
# `wmshell` IST PFLICHT, auch wenn hier niemand tippt: `wait_wm` wird
# NUR unter diesem Wort betreten (kgui.fi, `if mode_on(M_WMSHELL)`).
# Ohne es laeuft k15_start durch und der Kern beendet sich, bevor ein
# Klick moeglich waere -- gemessen: "kernel: done" nach 30 Sekunden.
# `wmdauer` haelt die Schleife danach offen.
# `hidgen` IST DER UNTERSCHIED ZWISCHEN MAUS UND KEINER MAUS.
# Ohne das Wort bleibt `usb.S_GEN` null, der generische HID-Weg ist
# gesperrt, und die QEMU-Maus (0627:0001, ohne brauchbares
# Boot-Protokoll in diesem Aufbau) liefert nichts: gemessen
# `mouse: id=3 packets=0` ueber den ganzen Lauf. `pruef/oneshot.py`,
# der einzige Laeufer dieses Baums, der WIRKLICH klickt, setzt es
# ebenfalls -- hier stand es nur nie, weil vor dieser Runde niemand
# im Dateimanager geklickt hat.
APP = ("gfx wm wigfiles wmshell wmdauer herz hidgen "
       "nosched noproc nofs usb vfs fbres=%dx%d" % (BREIT, HOCH))
kvm = (["-accel", "kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK)
       else ["-accel", "tcg"])
q = ["qemu-system-x86_64"] + kvm + [
    "-kernel", os.path.join(ARB, "k.mb"), "-m", "512",
    "-append", APP, "-display", "none", "-no-reboot", "-vga", "std",
    "-serial", "file:" + SER,
    "-monitor", "unix:%s,server,nowait" % SOCK,
    "-drive", "file=%s,format=raw,if=ide,index=0" % os.path.join(ARB, "live-knopf.img"),
    "-device", "qemu-xhci,id=xhci",
    "-device", "usb-mouse", "-device", "usb-kbd",
    "-device", "isa-debug-exit,iobase=0xf4,iosize=0x04",
]
p = subprocess.Popen(q, stdout=open(os.path.join(ARB, "knopf-qemu.log"), "w"),
                     stderr=subprocess.STDOUT)
sag("QEMU pid=%d" % p.pid)

rc = 1
try:
    # In der Schreibtischschleife gibt es kein `wm: hold` -- gewartet
    # wird auf das Fenster des Dateimanagers selbst.
    if not warte_auf(r"wlib: win id=\d+ x=\d+ y=\d+ w=\d+ h=\d+", 180,
                     "das Fenster des Dateimanagers steht"):
        raise SystemExit(1)
    # Der Dateimanager ist gross; sein Fenster steht nicht im selben
    # Augenblick wie der Fensterserver.
    if not warte_auf(r"explorer: orte n=\d+", 120, "die Seitenleiste steht"):
        raise SystemExit(1)
    time.sleep(6)

    m = Maschine(SOCK, BREIT, HOCH)
    m.verbinde()
    m.foto(os.path.join(ARB, "10-ohne.ppm"))
    sag("Bild 1: die Leiste ohne Stick")

    vor = len(re.findall(r"explorer: orte n=(\d+) traeger=(\d+)", lies()))

    # ---------------------------------------------- der Stick kommt
    m.sag("drive_add 0 id=stk,if=none,file=%s,format=raw"
          % os.path.join(ARB, "stick.img"))
    m.sag("device_add usb-storage,id=devstk,drive=stk,bus=xhci.0")
    sag("Stick gesteckt (device_add usb-storage)")
    if not warte_auf(r"wechsel: kommt", 90, "der Kern haengt ihn ein"):
        raise SystemExit(1)

    # DIE ZUSAGE DIESER RUNDE: OHNE ZUTUN. Kein F5, kein Klick --
    # der Dateimanager haengt am Bus und liest die Orte von selbst neu.
    got = False
    t0 = time.time()
    while time.time() - t0 < 60:
        tr = re.findall(r"explorer: orte n=\d+ traeger=(\d+)", lies())
        if tr and int(tr[-1]) >= 1:
            got = True
            break
        time.sleep(0.5)
    sag("Stick in der Leiste OHNE Zutun: %s (traeger=%s)"
        % ("JA" if got else "NEIN", tr[-1] if tr else "?"))
    time.sleep(3)
    m.foto(os.path.join(ARB, "20-steckt.ppm"))
    sag("Bild 2: der Stick steht in der Leiste")

    # ------------------------------------- den Auswurfknopf finden
    txt = lies()
    # DIE LAGE DES FENSTERS. `wlib` meldet sie selbst, sobald das
    # Fenster steht -- `wm: win ...` kommt erst beim Halt und ist
    # deshalb hier nicht da. Die Rechtecke unten sind fensterrelativ,
    # also ist das die Zahl, auf die alles andere aufsetzt.
    wins = re.findall(r"wlib: win id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)
    if not wins:
        sag("kein Fenster des Dateimanagers im Bericht")
        raise SystemExit(1)
    wx, wy, ww, wh = (int(v) for v in wins[-1])
    sag("Fenster des Dateimanagers: x=%d y=%d w=%d h=%d" % (wx, wy, ww, wh))

    rects = re.findall(
        r"explorer: rect id=(\d+) kind=(\d+) x=(-?\d+) y=(-?\d+) w=(\d+) h=(\d+)",
        txt)
    if not rects:
        sag("KEIN Bedienelement gemeldet -- liegt /etc/uitrace auf der Platte?")
        raise SystemExit(1)
    sag("%d gemeldete Bedienelemente" % len(rects))

    # Der Auswurfknopf ist der LETZTE Symbolknopf vor dem Starterknopf;
    # seine Nummer steht im Mitschnitt hinter `explorer: auswerfen id=`.
    zid = re.findall(r"explorer: ausknopf id=(\d+)", txt)
    ziel = None
    if zid:
        for r in rects:
            if r[0] == zid[-1]:
                ziel = r
        sag("Auswurfknopf gemeldet als id=%s" % zid[-1])
    if ziel is None:
        sag("die Nummer des Auswurfknopfes steht nicht im Mitschnitt")
        raise SystemExit(1)

    _id, _k, rx, ry, rw, rh = ziel
    cx = wx + int(rx) + int(rw) // 2
    cy = wy + int(ry) + int(rh) // 2
    sag("Klick auf GEMELDETE Koordinaten: (%d,%d) "
        "[Fenster %d,%d + Rechteck %s,%s %sx%s]"
        % (cx, cy, wx, wy, rx, ry, rw, rh))

    # ERST DEN STICK IN DER LEISTE AUSWAEHLEN. Der Knopf wirft den
    # AUSGEWAEHLTEN Traeger aus und sagt sonst "keiner da"
    # (`auswerfen_klick`: `ort_wahl >= places_num()`). Die Zeile wird
    # nicht abgezaehlt, sondern gemeldet -- `explorer: ortzeile i= y= h=`
    # aus `orte_anzeigen`, das bei jedem Neulesen laeuft.
    liste = None
    oid = re.findall(r"explorer: orteliste id=(\d+)", txt)
    if oid:
        for r in rects:
            if r[0] == oid[-1]:
                liste = r
    zeilen = re.findall(r"explorer: ortzeile i=(\d+) y=(-?\d+) h=(\d+)", txt)
    if liste is None or not zeilen:
        sag("Ortsliste oder Traegerzeile nicht gemeldet "
            "(liste=%s zeilen=%d)" % (liste is not None, len(zeilen)))
        raise SystemExit(1)
    lx, ly, lw = int(liste[2]), int(liste[3]), int(liste[4])
    # Die LETZTE gemeldete Traegerzeile ist der Stick: die Wurzel steht
    # davor, weil `carrier_read` die Einhaengungen der Reihe nach liest.
    zi, zy, zh = (int(v) for v in zeilen[-1])
    zx = wx + lx + lw // 2
    zyy = wy + ly + zy + zh // 2
    sag("Traegerzeile i=%d auswaehlen bei GEMELDETEN (%d,%d)" % (zi, zx, zyy))
    m.klick_auf(zx, zyy)
    time.sleep(2)

    m.klick_auf(cx, cy)
    time.sleep(4)
    if not warte_auf(r"explorer: auswerfen", 30, "der Knopf hat gefeuert"):
        pass
    time.sleep(3)
    m.foto(os.path.join(ARB, "30-ausgeworfen.ppm"))
    sag("Bild 3: nach dem Klick auf den Auswurfknopf")
    rc = 0
finally:
    try:
        p.terminate()
        p.wait(timeout=10)
    except Exception:
        try:
            p.kill()
        except Exception:
            pass

# ------------------------------------------------------------ die Bilder
try:
    from PIL import Image
    for n in ("10-ohne", "20-steckt", "30-ausgeworfen"):
        s = os.path.join(ARB, n + ".ppm")
        if os.path.exists(s) and os.path.getsize(s) > 0:
            Image.open(s).save(os.path.join(AUS, n + ".png"))
            sag("%s.png (%d Oktette)"
                % (n, os.path.getsize(os.path.join(AUS, n + ".png"))))
except ImportError:
    sag("PIL fehlt -- die PPM bleiben liegen")

open(os.path.join(ARB, "knopf-befund.txt"), "w").write("\n".join(befund) + "\n")
sys.exit(rc)
