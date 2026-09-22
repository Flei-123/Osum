#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""g006.py -- DER RADIUS FUER FENSTER OHNE SCHMUCK, IM BILD (G-006).

    python3 pruef/g006.py <bauverzeichnis> [ausgabeverzeichnis]

WAS GEMESSEN WIRD und warum es ein BILD braucht.

`OFFEN.md` G-006: "F_NODECO-Fenster (Schreibtisch, Taskleiste, wmshell,
Kontrollzentrum) laufen durch einen reinen Blit-Pfad und bekommen NIE
einen Radius". Ob das behoben ist, steht in keiner Zahl auf der
seriellen Leitung -- es steht in den vier Ecken des Fensters. Also wird
nachgesehen, und zwar so, dass die Antwort nicht von einem Blick
abhaengt:

DIE ECKE WIRD GEZAEHLT, NICHT BETRACHTET. In einem Quadrat von r x r
Bildpunkten an der Fensterecke haben bei einer ECKIGEN Ecke alle
Punkte die Fensterfarbe; bei einer RUNDEN gehoert ungefaehr ein
Viertel (1 - pi/4 = 21 %) zum Untergrund. Gezaehlt wird also, wieviele
Punkte im Eckquadrat NICHT die Farbe der Fenstermitte haben.

DIE GEGENPROBE GEHOERT DAZU und ist der eigentliche Beweis: derselbe
Lauf mit `shape=classic` (FM_RADIUS = 0) muss die Ecke VOLL finden.
Ohne sie misst dieser Laeufer nur, dass irgendwo etwas anders ist als
in der Mitte -- ein Schatten taete das auch.
"""
import os
import re
import subprocess
import sys
import time

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
sys.path.insert(0, HIER)
from klick import Maschine

BUILD = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "/root/drei-lg-g"
# Das Abbild der GEGENPROBE: dasselbe Repo, gebaut mit THEMA=werkstatt
# (shape=classic, also FM_RADIUS = 0).
CLASSIC = os.environ.get("CLASSIC_BUILD", "/root/drei-lg-c")
AUS = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 \
      else os.path.join(WURZEL, "belege", "g006")
os.makedirs(AUS, exist_ok=True)

OK = [0]
FAIL = [0]
ZEILEN = []


def sag(*a):
    s = " ".join(str(x) for x in a)
    print(s, flush=True)
    ZEILEN.append(s)


def ok(*a):
    OK[0] += 1
    sag("  OK   ", *a)


def bad(*a):
    FAIL[0] += 1
    sag("  FAIL ", *a)


def lauf(name, build):
    """Eine Maschine hochfahren, das Kontrollzentrum aufmachen, Foto.

    DIE FORM KOMMT AUS DEM ABBILD UND NICHT VON DER KOMMANDOZEILE.
    Ein erster Anlauf haengte `shape=classic` an die Kernelzeile -- der
    Kern hat es klaglos geschluckt und weiter mit `radius=12` gemalt
    (`glas alpha=100 blur=8 radius=12` stand in BEIDEN Laeufen auf der
    Leitung). Die Form steht in `/etc/theme.conf`, und die schreibt
    `tools/usbimg/build.sh` aus dem Thema (`THEMA=werkstatt` ->
    shape=classic). Die Gegenprobe braucht deshalb ein ZWEITES ABBILD
    und nicht ein zweites Wort."""
    d = os.path.join(HIER, "laeufe", "g006-" + name)
    os.makedirs(d, exist_ok=True)
    ser = os.path.join(d, "serial.txt")
    sock = os.path.join(d, "mon.sock")
    for f in (ser, sock):
        if os.path.exists(f):
            os.unlink(f)
    cl = ("modfs osum gfx wm wig desk wmshell wmdauer herz absturzhalt "
          "nopuls tz=120 usb hidgen nosched noproc nofs fbres=1280x800 "
          "lang=de")
    kvm = ["-accel", "kvm", "-cpu", "host"] \
        if os.access("/dev/kvm", os.W_OK) else ["-accel", "tcg"]
    q = (["qemu-system-x86_64"] + kvm +
         ["-m", "512", "-smp", "2",
          "-kernel", os.path.join(build, "osum.mb"),
          "-initrd", os.path.join(build, "root.img"),
          "-append", cl, "-vga", "std",
          "-device", "qemu-xhci,id=xhci",
          "-device", "usb-mouse", "-device", "usb-kbd",
          "-serial", "file:" + ser,
          "-monitor", "unix:%s,server,nowait" % sock,
          "-display", "none", "-no-reboot"])
    p = subprocess.Popen(q, stdout=open(os.path.join(d, "qemu.txt"), "w"),
                         stderr=subprocess.STDOUT)
    m = Maschine(sock, 1280, 800)
    m.verbinde()
    t0 = time.time()
    while time.time() - t0 < 90:
        try:
            if "taskbar: state" in open(ser, "rb").read().decode(
                    "utf-8", "replace"):
                break
        except OSError:
            pass
        time.sleep(1)
    time.sleep(8)
    # SUPER+A macht das Kontrollzentrum auf -- ein Fenster OHNE Schmuck,
    # das NICHT den ganzen Schirm bedeckt und keinen Rand reserviert.
    # Genau der Fall, den G-006 nennt.
    m.taste("meta_l-a")
    time.sleep(4)
    bild = os.path.join(AUS, name + ".png")
    m.foto(bild)
    txt = open(ser, "rb").read().decode("utf-8", "replace")
    m.sag("quit")
    time.sleep(1)
    try:
        p.kill()
    except Exception:
        pass
    return bild, txt


def profil(bild, x0, y0, r, mitte):
    """Das PROFIL der oberen linken Ecke: wo faengt in Zeile dy die
    Fensterfarbe an?

    DIE ZAEHLUNG IM QUADRAT WAR ZU GROB, und das hat die Gegenprobe
    gezeigt: das Kontrollzentrum malt seine Flaeche mit `draw_board`
    und rundet sich damit SELBST -- auch bei FM_RADIUS = 0. Im
    10x10-Quadrat kamen deshalb 44 % (rund) gegen 19 % (eckig) heraus,
    und 19 % sind nicht null.

    Das PROFIL trennt beides sauber. Eine runde Ecke rueckt Zeile fuer
    Zeile ein:

        rund     dy=1 -> 9   dy=2 -> 6   dy=3 -> 5   dy=4 -> 4 ...
        eckig    dy=1 -> 1   dy=2 -> 1   dy=3 -> 1   dy=4 -> 1 ...

    Gemessen wird die SUMME der Einzuege ueber die ersten `r` Zeilen.
    Sie ist bei einer runden Ecke ungefaehr r*r*(1 - pi/4), bei einer
    eckigen hoechstens ein paar Bildpunkte Rand."""
    from PIL import Image
    im = Image.open(bild).convert("RGB")
    p = im.load()
    summe = 0
    zeilen = []
    for dy in range(0, r):
        y = y0 + dy
        if y >= im.size[1]:
            continue
        ein = r
        for dx in range(0, r):
            x = x0 + dx
            if x < im.size[0] and p[x, y] == mitte:
                ein = dx
                break
        summe += ein
        zeilen.append(ein)
    return summe, zeilen


def rechteck(txt):
    """Die Lage des Kontrollzentrums, aus SEINEM eigenen Bericht.

    `qs: geo x= y= w= h=` -- das Programm sagt selbst, wo es steht.
    Ein erster Anlauf suchte das letzte `wlib: win` und traf damit das
    TERMINAL (8,374 440x418) statt des Kontrollzentrums."""
    w = re.findall(r"qs: geo x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)
    if w:
        return tuple(int(v) for v in w[-1])
    return None


def main():
    from PIL import Image
    # ---------------------------------------------------- 1. osum (rund)
    b1, t1 = lauf("osum", BUILD)
    r1 = rechteck(t1)
    if not r1:
        bad("die Lage des Fensters steht nicht im Bericht")
        sag("       " + " / ".join(
            [z for z in t1.splitlines() if "qs:" in z][:4]))
        return 1
    x, y, bw, bh = r1
    ok("das Fenster steht bei %d,%d %dx%d" % (x, y, bw, bh))
    g1r = re.findall(r"glas alpha=(\d+) blur=(\d+) radius=(\d+)", t1)
    if g1r:
        sag("       der Kern meldet: alpha=%s blur=%s radius=%s"
            % g1r[-1])
    im = Image.open(b1).convert("RGB")
    mitte = im.load()[x + bw // 2, y + bh // 2]
    sag("       Farbe der Fenstermitte: %s" % (mitte,))
    R = 12
    s1, z1 = profil(b1, x, y, R, mitte)
    sag("       Profil der Ecke (Einzug je Zeile): %s" % z1)
    sag("       Summe der Einzuege: %d" % s1)

    # ------------------------------------------ 2. GEGENPROBE: classic
    b2, t2 = lauf("classic", CLASSIC)
    r2 = rechteck(t2)
    if not r2:
        bad("GEGENPROBE: die Lage des Fensters fehlt")
        return 1
    x2, y2, bw2, bh2 = r2
    im2 = Image.open(b2).convert("RGB")
    mitte2 = im2.load()[x2 + bw2 // 2, y2 + bh2 // 2]
    g2r = re.findall(r"glas alpha=(\d+) blur=(\d+) radius=(\d+)", t2)
    if g2r:
        sag("       GEGENPROBE, der Kern meldet: alpha=%s blur=%s radius=%s"
            % g2r[-1])
        if g2r[-1][2] != "0":
            bad("GEGENPROBE: das Abbild hat radius=%s statt 0 -- mit "
                "THEMA=werkstatt bauen" % g2r[-1][2])
    s2, z2 = profil(b2, x2, y2, R, mitte2)
    sag("       GEGENPROBE, Profil: %s" % z2)
    sag("       GEGENPROBE, Summe: %d" % s2)
    # DIE EIGENTLICHE ZUSAGE: rund UND eckig, und der Abstand dazwischen.
    if s1 > s2 * 2 and s1 >= R:
        ok("RUND gegen ECKIG: Einzugssumme %d gegen %d -- die Ecke "
           "dieses Fensters wird WEGEN FM_RADIUS ausgespart und nicht "
           "wegen eines Schattens" % (s1, s2))
    else:
        bad("kein Unterschied: rund %d, eckig %d" % (s1, s2))
    # Und die Form der Rundung: sie muss MONOTON fallen. Eine Treppe,
    # die wieder ansteigt, waere ein Rechenfehler und keine Ecke.
    fallend = all(z1[k] >= z1[k + 1] for k in range(len(z1) - 1))
    if fallend:
        ok("die Rundung faellt monoton (%s) -- eine echte Viertelkurve"
           % z1)
    else:
        bad("das Profil ist keine Kurve: %s" % z1)

    open(os.path.join(AUS, "BEFUND.txt"), "w").write("\n".join(ZEILEN) + "\n")
    sag("")
    sag("G-006: %d bestanden, %d gescheitert" % (OK[0], FAIL[0]))
    return 1 if FAIL[0] else 0


sys.exit(main())
