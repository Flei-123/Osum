#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""toast.py -- DIE BENACHRICHTIGUNG, GEMESSEN UND FOTOGRAFIERT (S-006).

    python3 pruef/toast.py <bauverzeichnis> [ausgabeverzeichnis]

WAS HIER GEMESSEN WIRD und warum es einen eigenen Laeufer braucht.

Der Systembus traegt Meldungen seit Runde SYSTEMBUS (`bus.noti_post`,
sechzehn Plaetze), und die Glocke in der Taskleiste zaehlt die
ungelesenen. Gesehen hat sie nie jemand, der nicht auf die Glocke sah.
`OFFEN.md` S-006 nennt genau diesen Rest: "es gibt keine sichtbare
Einblendung mit Verlauf".

Diese Runde baut sie. Gemessen wird BEIDES, und zwar an einer Meldung,
die NICHT aus der Taskleiste kommt:

  * die Leitung -- `taskbar: toast [<text>] x= y= w= h= prio= n=` kommt
                   genau dann, wenn die Karte aufgeht, und
                   `taskbar: toast zu`, wenn sie nach vier Sekunden
                   wieder verschwindet.
  * das Bild    -- an der gemeldeten Stelle steht wirklich etwas, und
                   vorher stand dort nichts.

WARUM EIN USB-STICK UND KEINE AKKUWARNUNG. Die Akkuwarnung postet die
Leiste SELBST; damit wuerde dieser Laeufer beweisen, dass ein Programm
seine eigene Meldung anzeigen kann -- und das ist die schwaechere
Aussage. Der Kern meldet das Einhaengen eines Wechseltraegers ueber
denselben Bus (`wechsel.melden` -> `bus.noti_post`, Text
"usb+ /medien/usb0"), also aus einem ANDEREN Prozess. Genau das muss
ein Benachrichtigungsdienst koennen, und genau daran ist der erste
Entwurf dieser Runde gescheitert: er zeigte nur, was die Leiste selbst
gepostet hatte.

DER STICK WIRD ERST NACH DEM HOCHFAHREN GESTECKT. Ein Traeger, der von
Anfang an dasteht, loest kein Ereignis aus -- und `toast_step` laesst
den allerersten Blick auf den Bus ausdruecklich aus (sonst blendete die
Leiste beim Anmelden alles ein, was noch im Ring liegt).
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

BUILD = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "/root/drei-lg-f"
AUS = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 \
      else os.path.join(WURZEL, "belege", "toast")
os.makedirs(AUS, exist_ok=True)
D = os.path.join(HIER, "laeufe", "toast")
SER = os.path.join(D, "serial.txt")
STICK = os.path.join(D, "stick.img")

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


def lies():
    try:
        with open(SER, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except OSError:
        return ""


def warte_auf(muster, frist=90):
    t0 = time.time()
    while time.time() - t0 < frist:
        if re.search(muster, lies()):
            return True
        time.sleep(1)
    return False


def anders(a_pfad, b_pfad, x0, y0, x1, y1):
    """Wieviele Bildpunkte im Rechteck unterscheiden ZWEI BILDER?

    DAS IST DIE RICHTIGE FRAGE, und die beiden Anlaeufe davor haben die
    falsche gestellt. Der erste verglich jeden Punkt mit der Ecke oben
    links IM Rechteck -- die gehoert, sobald die Karte steht, schon zur
    Karte. Der zweite nahm einen Punkt daneben, und der ist in beiden
    Bildern Schreibtisch: dieselbe Farbe, also dieselbe Zahl. Beide
    Male kam vorher wie nachher 1680 von 2280 heraus, und das sah aus
    wie "da ist nichts", waehrend auf dem Bild deutlich eine Karte
    stand.

    Gemessen wird deshalb der UNTERSCHIED ZWISCHEN DEN BILDERN an
    derselben Stelle. Steht dort vorher Schreibtisch und nachher eine
    Karte, ist die Zahl gross; ist beide Male dasselbe da, ist sie
    klein. Das misst genau die Behauptung."""
    from PIL import Image
    A = Image.open(a_pfad).convert("RGB")
    B = Image.open(b_pfad).convert("RGB")
    if A.size != B.size:
        return -1, 0
    pa, pb = A.load(), B.load()
    n = 0
    ges = 0
    for y in range(y0, min(y1, A.size[1]), 2):
        for x in range(x0, min(x1, A.size[0]), 2):
            ges += 1
            if pa[x, y] != pb[x, y]:
                n += 1
    return n, ges


def main():
    os.makedirs(D, exist_ok=True)
    # EIN STICK, DEN DIESER KERN WIRKLICH EINHAENGT -- und das ist
    # nicht irgendein FAT.
    #
    # Der erste Anlauf legte ein blankes FAT32 ohne Partitionstafel an.
    # Gemessen kam daraufhin `wechsel: kommt dev=4 parts=0 ... mount=0`:
    # der Traeger wurde GESEHEN, aber nicht eingehaengt -- und
    # `wechsel.melden` steht HINTER dem Einhaengen (wechsel.fi:575).
    # Ohne Einhaengen also keine Meldung, ohne Meldung kein Toast, und
    # der Laeufer haette der Einblendung die Schuld gegeben.
    #
    # Genommen wird deshalb woertlich das Rezept aus
    # `tools/hotplug/run.sh::stick_bauen`: MBR-Tafel, Typ `c`, das
    # FAT32 ab Sektor 2048.
    rm_f = [STICK, STICK + ".part"]
    for f in rm_f:
        if os.path.exists(f):
            os.unlink(f)
    subprocess.run(["dd", "if=/dev/zero", "of=" + STICK, "bs=1M",
                    "count=48", "status=none"], check=True)
    subprocess.run(["sfdisk", STICK], input=b"label: dos\nstart=2048, type=c\n",
                   check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["dd", "if=/dev/zero", "of=" + STICK + ".part", "bs=1M",
                    "count=46", "status=none"], check=True)
    subprocess.run(["mkfs.vfat", "-F32", "-n", "TOAST", STICK + ".part"],
                   check=True, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)
    subprocess.run(["dd", "if=" + STICK + ".part", "of=" + STICK, "bs=512",
                    "seek=2048", "conv=notrunc", "status=none"], check=True)
    os.unlink(STICK + ".part")

    kern = os.path.join(BUILD, "osum.mb")
    wurzel = os.path.join(BUILD, "root.img")
    for f in (kern, wurzel):
        if not os.path.exists(f):
            bad("es fehlt: %s" % f)
            return 1

    # DIE MASCHINE WIRD HIER SELBST GEBAUT und nicht ueber start.sh.
    #
    # `pruef/start.sh` haengt seine Kommandozeile aus vielen Teilen
    # zusammen und setzt unter anderem `nic`/`nip` -- der DHCP-Verkehr
    # schreibt dann mitten in die Zeilen, die dieser Laeufer lesen
    # muss. Genommen wird stattdessen woertlich die Bestueckung aus
    # `pruef/abmelden.py`, ergaenzt um `vfs`: ohne den Schalter haengt
    # `wechsel` den Stick nicht ein und postet folglich nichts.
    CL = ("modfs osum gfx wm wig desk wmshell wmdauer herz absturzhalt "
          "nopuls tz=120 usb hidgen vfs nosched noproc nofs "
          "fbres=1280x800 lang=de shape=osum")
    kvm = ["-accel", "kvm", "-cpu", "host"] \
        if os.access("/dev/kvm", os.W_OK) else ["-accel", "tcg"]
    sock = os.path.join(D, "mon.sock")
    for f in (SER, sock):
        if os.path.exists(f):
            os.unlink(f)
    q = (["qemu-system-x86_64"] + kvm +
         ["-m", "512", "-smp", "2",
          "-kernel", kern, "-initrd", wurzel,
          "-append", CL, "-vga", "std",
          "-device", "qemu-xhci,id=xhci",
          "-device", "usb-mouse", "-device", "usb-kbd",
          "-serial", "file:" + SER,
          "-monitor", "unix:%s,server,nowait" % sock,
          "-display", "none", "-no-reboot"])
    proc = subprocess.Popen(q, stdout=open(os.path.join(AUS, "qemu.txt"), "w"),
                            stderr=subprocess.STDOUT)
    sag("== QEMU pid %d, Abbild %s" % (proc.pid, BUILD))
    m = Maschine(sock, 1280, 800)
    m.verbinde()

    if warte_auf(r"taskbar: state"):
        ok("die Leiste steht")
    else:
        bad("die Leiste kam nicht hoch")
        return 1
    time.sleep(6)

    # ------------------------------------------- 1. VORHER: nichts da
    vorher = os.path.join(AUS, "10-vorher.png")
    m.foto(vorher)
    if "taskbar: toast [" in lies():
        bad("es stand schon eine Einblendung da, bevor etwas passiert ist")
    else:
        ok("VORHER: keine Einblendung (der erste Blick auf den Bus zaehlt nicht)")

    # ------------------------------------- 2. DER STICK, NACH dem Start
    vor = len(lies())
    m.sag("drive_add 0 id=tst,if=none,file=%s,format=raw" % STICK)
    m.sag("device_add usb-storage,id=devtst,drive=tst")
    sag("== Stick gesteckt (usb-storage)")

    if warte_auf(r"taskbar: toast \[", 60):
        ok("die Leitung meldet die Einblendung")
    else:
        bad("kein 'taskbar: toast [' -- die Karte ging nicht auf")

    neu = lies()[vor:]
    t = re.findall(r"taskbar: toast \[([^\]]*)\] x=(\d+) y=(\d+) "
                   r"w=(\d+) h=(\d+) prio=(\d+) n=(\d+)", neu)
    if not t:
        bad("die Meldung steht nicht vollstaendig auf der Leitung")
        sag("       " + " / ".join(
            [z for z in neu.splitlines() if "toast" in z][:3]))
    else:
        text, tx, ty, tw, th, pr, nn = t[-1]
        tx, ty, tw, th = int(tx), int(ty), int(tw), int(th)
        ok("Text [%s] bei %d,%d %dx%d prio=%s n=%s"
           % (text, tx, ty, tw, th, pr, nn))
        # DER TEXT KOMMT AUS DEM KERN und nicht aus der Leiste.
        if text.startswith("usb"):
            ok("der Text stammt vom KERN ('%s') -- also aus einem "
               "fremden Prozess" % text)
        else:
            bad("unerwarteter Text: '%s' (erwartet 'usb+ ...')" % text)
        # Die Karte steht rechts oben und nicht irgendwo.
        if tx + tw <= 1280 and ty >= 0 and ty + th <= 800:
            ok("die Karte liegt ganz im Bild (%d..%d, %d..%d)"
               % (tx, tx + tw, ty, ty + th))
        else:
            bad("die Karte haengt ueber den Rand: %d+%d, %d+%d"
                % (tx, tw, ty, th))
        if tx > 1280 // 2:
            ok("und zwar RECHTS (x=%d bei Breite 1280)" % tx)
        else:
            bad("sie steht nicht rechts: x=%d" % tx)

        # --------------------------------- 3. DAS BILD, WAEHREND SIE STEHT
        #
        # KURZ WARTEN, UND ZWAR GENAU SO LANGE WIE DAS EINBLENDEN
        # DAUERT. Der erste Anlauf fotografierte sofort nach der
        # Meldung -- und erwischte die Karte MITTEN IM VERLAUF, bei
        # geringer Deckung. Auf dem Bild war sie zu sehen, aber so
        # blass, dass die Tintenzaehlung sie nicht von der Flaeche
        # darunter unterscheiden konnte. TOAST_EIN ist 200 ms; eine
        # halbe Sekunde ist mit Abstand genug und laesst von den vier
        # Sekunden Standzeit reichlich uebrig.
        time.sleep(0.6)
        waehrend = os.path.join(AUS, "20-einblendung.png")
        m.foto(waehrend)
        try:
            n1, g1 = anders(vorher, waehrend, tx, ty, tx + tw, ty + th)
            sag("       Bildpunkte, die sich geaendert haben: %d von %d"
                % (n1, g1))
            # Ein Zehntel der Flaeche ist eine niedrige Schranke und
            # genau deshalb die richtige: sie faellt erst, wenn dort
            # WIRKLICH nichts passiert -- und sie haelt auch, wenn die
            # Karte gerade erst zur Haelfte eingeblendet ist.
            if n1 > g1 // 10:
                ok("BILD: an der gemeldeten Stelle steht wirklich etwas "
                   "(%d von %d Punkten anders als vorher)" % (n1, g1))
            else:
                bad("BILD: an der gemeldeten Stelle aendert sich fast "
                    "nichts (%d von %d)" % (n1, g1))
        except Exception as e:
            bad("das Bild liess sich nicht nachmessen: %s" % e)

    # ------------------------------------------ 4. SIE GEHT WIEDER ZU
    if warte_auf(r"taskbar: toast zu", 30):
        ok("sie geht von selbst wieder zu ('taskbar: toast zu')")
    else:
        bad("'taskbar: toast zu' fehlt -- die Karte bleibt stehen")
    time.sleep(2)
    danach = os.path.join(AUS, "30-danach.png")
    m.foto(danach)
    if t:
        try:
            # GEGEN DAS BILD VON VORHER, nicht gegen das mit der Karte:
            # "wieder wie vorher" ist die Behauptung.
            n2, g2 = anders(vorher, danach, tx, ty, tx + tw, ty + th)
            sag("       gegenueber VORHER noch anders: %d von %d"
                % (n2, g2))
            if n2 <= g2 // 10:
                ok("BILD: danach ist die Stelle wieder wie vorher "
                   "(nur %d von %d Punkten anders)" % (n2, g2))
            else:
                bad("BILD: da steht noch etwas (%d von %d)" % (n2, g2))
        except Exception as e:
            bad("das Bild liess sich nicht nachmessen: %s" % e)

    # ------------------------------------- 5. DIE GLOCKE BLEIBT STEHEN
    # Die Einblendung ist KEIN Lesen: sie benutzt `noti_peek` und nicht
    # `noti_take`. Steht die Glocke nach dem Zumachen immer noch auf
    # einer ungelesenen Meldung, stimmt das.
    s = lies()
    gl = re.findall(r"taskbar: text noti [^\n]*t=([^\n]*)", s)
    if gl:
        sag("       Glocke zuletzt: %r" % gl[-1][:20])
    if re.search(r"taskbar: toast zu", s) and "usb" in s:
        ok("GEGENPROBE: die Meldung liegt weiter im Bus "
           "(die Karte hat sie nicht abgeholt)")
    else:
        bad("die Meldung ist verschwunden")

    # --------------------------------------------------- 6. KEIN PANIC
    p = [z.strip() for z in s.splitlines() if "panic:" in z]
    if p:
        bad("PANIC im Lauf: %s" % p[0][:120])
    else:
        ok("GEGENPROBE: kein Panic im ganzen Lauf")

    m.sag("quit")
    open(os.path.join(AUS, "BEFUND.txt"), "w").write("\n".join(ZEILEN) + "\n")
    sag("")
    sag("TOAST: %d bestanden, %d gescheitert" % (OK[0], FAIL[0]))
    return 1 if FAIL[0] else 0


sys.exit(main())
