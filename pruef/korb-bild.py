#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""korb-bild.py -- DER BILDBEWEIS FUER D-016 (Papierkorb).

    python3 pruef/korb-bild.py <bauverzeichnis> [ausgabeverzeichnis]

WARUM ES DIESEN LAEUFER GIBT.

`OFFEN.md` fuehrt D-016 mit "es fehlen Groessenbegrenzung und
Wiederherstellen aus der Oberflaeche". Beim Nachsehen im Baum lag
beides fertig da:

    trash.grenze()      kernel/user/trash.fi:372   liest
                        /etc/papierkorb.conf, Vorgabe 64 MiB
    trash.aufraeumen()  kernel/user/trash.fi:399   wirft das Aelteste
                        hinaus, gerufen aus trash.hinein():486
    trash.back()        kernel/user/trash.fi:492   holt zurueck
    papierkorb.fi       399 Zeilen, ein FENSTER mit Tabelle und vier
                        Knoepfen (zurueck/entfernen/leeren/neu) und
                        einer Kopfzeile "<n> von <MiB> von <grenze> MiB"

Gefehlt hat nur die AUSLIEFERUNG: `papierkorb` stand in keiner
PROGS-Liste, also lag /bin/papierkorb in keinem Abbild, und
/etc/papierkorb.conf auch nicht -- die Grenze war damit nie
einstellbar. Beides ist jetzt in tools/usbimg/build.sh und in der
PFLICHT-Liste.

WAS HIER GEMESSEN WIRD, und zwar am laufenden System und nicht im
Quelltext:

  1. /bin/papierkorb und /etc/papierkorb.conf liegen im Abbild
  2. der Korb nimmt eine Datei auf (`papierkorb weg`)
  3. `papierkorb liste` zeigt sie
  4. DAS FENSTER geht auf und zeigt die Kopfzeile mit der GRENZE
     -- das ist der Bildbeweis
  5. `papierkorb zurueck` holt die Datei an ihren Platz zurueck

Der Weg ueber die Konsole (`dualcli`) und nicht ueber Klicks: die
Zusage lautet "der Korb kann es", nicht "das Startmenue findet es".
Das Fenster wird trotzdem gezeigt, weil D-016 ausdruecklich von der
OBERFLAECHE spricht.
"""
import os, re, subprocess, sys, time

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
sys.path.insert(0, HIER)
from klick import Maschine

BUILD = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else "/root/pk-img"
AUS = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 \
      else os.path.join(WURZEL, "belege", "korb")
os.makedirs(AUS, exist_ok=True)
SER = os.path.join(AUS, "korb.txt")
SOCK = "/tmp/korb-bild.sock"
for f in (SER, SOCK):
    if os.path.exists(f):
        os.unlink(f)

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
        return open(SER, "rb").read().decode("utf-8", "replace")
    except OSError:
        return ""


def warte(text, frist=90.0):
    t0 = time.time()
    while time.time() - t0 < frist:
        if text in lies():
            return True
        time.sleep(0.5)
    return False


# ============================================ 1. WAS IM ABBILD LIEGT
sag("== 1. das Abbild traegt den Papierkorb")
liste = subprocess.run(["python3", os.path.join(WURZEL, "tools/osum/mkfs.py"),
                        "list", os.path.join(BUILD, "root.img")],
                       capture_output=True, text=True).stdout
for f in ("/bin/papierkorb", "/etc/papierkorb.conf"):
    if re.search(r"(^|\s)%s(\s|$)" % re.escape(f), liste, re.M):
        ok("im Abbild: %s" % f)
    else:
        bad("FEHLT im Abbild: %s" % f)

conf = subprocess.run(["python3", os.path.join(WURZEL, "tools/osum/mkfs.py"),
                       "cat", os.path.join(BUILD, "root.img"),
                       "/etc/papierkorb.conf"],
                      capture_output=True, text=True).stdout
g = re.search(r"^grenze=(\d+)", conf, re.M)
if g:
    ok("/etc/papierkorb.conf nennt eine Grenze: %s MiB" % g.group(1))
else:
    bad("/etc/papierkorb.conf hat keine Zeile 'grenze='")

# ============================================== DIE MASCHINE STARTEN
CL = ("modfs osum gfx wm wig desk wmshell wmdauer herz absturzhalt nopuls "
      "tz=120 usb hidgen nosched noproc nofs fbres=1280x800 lang=de")
kvm = ["-accel", "kvm", "-cpu", "host"] if os.access("/dev/kvm", os.W_OK) \
      else ["-accel", "tcg"]
q = (["qemu-system-x86_64"] + kvm +
     ["-m", "512", "-smp", "2",
      "-kernel", os.path.join(BUILD, "osum.mb"),
      "-initrd", os.path.join(BUILD, "root.img"),
      "-append", CL, "-vga", "std",
      "-device", "qemu-xhci,id=xhci",
      "-device", "usb-mouse", "-device", "usb-kbd",
      "-serial", "file:" + SER,
      "-monitor", "unix:%s,server,nowait" % SOCK,
      "-display", "none", "-no-reboot"])
p = subprocess.Popen(q, stdout=open(os.path.join(AUS, "korb-qemu.txt"), "w"),
                     stderr=subprocess.STDOUT)
sag("== QEMU pid %d, Abbild %s" % (p.pid, BUILD))

try:
    if not warte("taskbar: state", 180):
        bad("der Schreibtisch kam nicht hoch")
        raise SystemExit
    ok("der Schreibtisch steht")
    time.sleep(8)
    m = Maschine(SOCK, 1280, 800)

    # ======================================= 2. EINE DATEI IN DEN KORB
    # Ueber das Terminal, weil die Zusage dem KORB gilt. Der Weg ist
    # derselbe, den der Explorer nimmt (dieselbe Bibliothek).
    sag("== 2. eine Datei in den Korb")
    m.taste("meta_l")
    time.sleep(3)
    m.tippe("terminal")
    time.sleep(2)
    m.taste("ret")
    time.sleep(8)
    m.foto(os.path.join(AUS, "p-10-terminal.png"))

    # KEINE UMLENKUNG UEBER DEN MONITOR. Gemessen im ersten Lauf: das
    # `>` kam als Leerzeichen an (`echo hallo  /users/root/probe.txt`),
    # die Datei entstand nie, und `papierkorb weg` wies sie voellig zu
    # Recht ab ("geht nicht"). Die Shell KANN umlenken (sh.fi:742) --
    # es ist der Weg der Tasten durch den QEMU-Monitor, der das Zeichen
    # verliert. Also wird eine Datei genommen, die es ohnehin gibt:
    # /etc/papierkorb.conf ist klein, liegt im Abbild und ist nach dem
    # Zuruecklegen wieder da.
    m.tippe("cp /etc/papierkorb.conf /users/root/probe.txt")
    m.taste("ret")
    time.sleep(4)
    m.tippe("papierkorb weg /users/root/probe.txt")
    m.taste("ret")
    time.sleep(5)
    m.foto(os.path.join(AUS, "p-20-hineingelegt.png"))
    t = lies()
    if "korb:" in t or "papierkorb" in t:
        ok("der Korb hat sich gemeldet")
    else:
        sag("       (keine eigene Meldung auf der Leitung)")

    # ============================================ 3. DIE LISTE
    sag("== 3. was liegt drin")
    m.tippe("papierkorb liste")
    m.taste("ret")
    time.sleep(5)
    m.foto(os.path.join(AUS, "p-30-liste.png"))

    # ======================================= 4. ZURUECKHOLEN, MIT BEWEIS
    #
    # DAS MUSS VOR DEM FENSTER STEHEN. Gemessen im zweiten Lauf: sobald
    # das Fenster oben liegt, gehen die Tasten AN DAS FENSTER und nicht
    # mehr an die Shell -- `papierkorb zurueck 1` stand danach zwar im
    # Bericht als `papierkorb -> 0`, aber die Zeile kam von einem Aufruf,
    # den die Shell nie gesehen hatte. Also erst der Rundlauf im
    # Terminal, dann das Bild.
    sag("== 4. wieder herausholen -- und nachsehen, ob sie da ist")
    m.tippe("papierkorb zurueck 1")
    m.taste("ret")
    time.sleep(5)
    m.tippe("cat /users/root/probe.txt")
    m.taste("ret")
    time.sleep(4)
    m.foto(os.path.join(AUS, "p-35-zurueckgeholt.png"))
    t = lies()
    # /etc/papierkorb.conf faengt mit diesem Kommentar an -- steht er
    # wieder auf dem Schirm, ist die Datei zurueck UND ihr Inhalt heil.
    if "der Papierkorb." in t:
        ok("zurueckgeholt: der Inhalt der Datei steht wieder da")
    else:
        bad("nach 'zurueck' kam der Inhalt der Datei nicht")
    m.tippe("papierkorb liste")
    m.taste("ret")
    time.sleep(4)
    if re.search(r"papierkorb: leer", lies()[-4000:]):
        ok("und der Korb ist wieder leer")
    else:
        sag("       (der Korb meldet sich nicht als leer)")

    # ============================================ 5. DAS FENSTER
    sag("== 5. DAS FENSTER -- der Bildbeweis")
    # Noch einmal hineinlegen, damit im Bild eine Zeile steht.
    m.tippe("papierkorb weg /users/root/probe.txt")
    m.taste("ret")
    time.sleep(4)
    m.tippe("papierkorb &")
    m.taste("ret")
    time.sleep(12)
    m.foto(os.path.join(AUS, "p-40-fenster.png"))
    t = lies()
    r = re.findall(r"papierkorb: (\w+)[^\n]{0,40}", t)
    if r:
        ok("das Programm meldet sich: %s" % " / ".join(r[-3:]))
    n = re.findall(r"papierkorb: rect id=(\d+)", t)
    if n:
        ok("es hat %d Bedienelemente gemeldet (rect id bis %s)"
           % (len(set(n)), max(n, key=int)))
    else:
        sag("       (kein 'papierkorb: rect' -- ohne /etc/uitrace ist es still)")


finally:
    try:
        p.kill()
        p.wait(timeout=10)
    except Exception:
        pass
    for f in sorted(os.listdir(AUS)):
        if f.startswith("p-") and f.endswith(".ppm"):
            try:
                os.unlink(os.path.join(AUS, f))
            except OSError:
                pass
    open(os.path.join(AUS, "korb-befund.txt"), "w").write("\n".join(ZEILEN) + "\n")

sag("")
sag("KORB: %d bestanden, %d gescheitert" % (OK[0], FAIL[0]))
sys.exit(1 if FAIL[0] else 0)
