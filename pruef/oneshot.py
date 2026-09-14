#!/usr/bin/env python3
"""oneshot.py <aus|neu|nein> -- EIN Aufruf: starten, klicken, urteilen.

Alles in EINEM Prozess, weil abgekoppelte Hintergrundlaeufe in dieser
Umgebung zwischen zwei Aufrufen sterben. Ergebnis steht in
/tmp/befund-<mode>.txt UND auf der Standardausgabe.
"""
import os, re, subprocess, sys, time
HIER = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HIER)
os.chdir(HIER)
from klick import Maschine
MODE = sys.argv[1] if len(sys.argv) > 1 else "aus"
NAME = "one-" + MODE
D = os.path.join(HIER, "laeufe", NAME); S = os.path.join(HIER, "shots", NAME)
subprocess.run(["rm", "-rf", D, S]); os.makedirs(D); os.makedirs(S)
SER = os.path.join(D, "serial.txt"); SOCK = "/tmp/one-%s.sock" % MODE
if os.path.exists(SOCK): os.unlink(SOCK)
LOG = open("/tmp/befund-%s.txt" % MODE, "w", buffering=1)
def sag(*a):
    print(*a); print(*a, file=LOG)
def lies():
    try: return open(SER, "rb").read().decode("utf-8", "replace")
    except OSError: return ""
def wins():
    return re.findall(r"wlib: win id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", lies())
CL = ("modfs osum gfx wm wig desk wmshell wmdauer herz absturzhalt nopuls "
      "tz=120 usb hidgen nic nip=169.254.10.1/16 nsvc=0 nwait=0 "
      "nosched noproc nofs fbres=1280x800")
kvm = ["-accel","kvm","-cpu","host"] if os.access("/dev/kvm", os.W_OK) else ["-accel","tcg"]
q = ["qemu-system-x86_64"] + kvm + ["-m","512","-smp","2",
     "-kernel", os.path.join(HIER,"osum.mb"), "-initrd", os.path.join(HIER,"root.img"),
     "-append", CL, "-vga","std", "-device","qemu-xhci,id=xhci",
     "-device","usb-mouse", "-device","usb-kbd",
     "-serial","file:"+SER, "-monitor","unix:%s,server,nowait"%SOCK,
     "-display","none"]
if MODE != "neu":
    q.append("-no-reboot")       # Ausschalten: die Maschine darf NICHT wiederkommen
p = subprocess.Popen(q, stdout=open(os.path.join(D,"qemu.txt"),"w"), stderr=subprocess.STDOUT)
sag("QEMU pid", p.pid, "mode", MODE, "(-no-reboot: %s)" % (MODE!="neu"))
t0=time.time()
while time.time()-t0 < 180:
    # NICHT nur "ready": erst wenn der Fensterserver das Fenster des
    # Starters (id=11) berichtet hat, steht seine Lage fest.
    if re.search(r"id=11 x=\d+ y=\d+ w=\d+ h=\d+", lies()): break
    if p.poll() is not None: sag("QEMU vorzeitig weg rc=",p.returncode); sys.exit(1)
    time.sleep(0.5)
sag("Starter bereit nach %.0fs" % (time.time()-t0))
time.sleep(3)
m = Maschine(SOCK, 1280, 800); m.verbinde()
m.foto(S+"/00-schreibtisch.ppm")
def fl():
    w=re.findall(r"id=11 [^\n]*fl=(\d+)", lies()); return w[-1] if w else "?"
sag("Startmenue fl=%s (18=offen, 19=zu)" % fl())
if fl() != "18":
    m.taste("meta_l"); time.sleep(3); sag("nach Super fl=%s" % fl())
m.foto(S+"/10-startmenue.ppm")
# --- Energieknopf: Lage aus dem Fensterbericht + bekanntem Layout
w11=re.findall(r"id=11 x=(\d+) y=(\d+) w=(\d+) h=(\d+)", lies())
gx,gy = int(w11[-1][0]), int(w11[-1][1])
r4=re.findall(r"launcher: rect id=4 kind=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", lies())
if r4: rx,ry,rw,rh=(int(v) for v in r4[-1])
else:  rx,ry,rw,rh=12,376,76,32       # gemessen im sauberen Lauf
cx,cy = gx+rx+rw//2, gy+ry+rh//2
sag("Energieknopf bei %d,%d (Fenster %d,%d)" % (cx,cy,gx,gy))
vor=set(wins())
m.klick_auf(cx,cy); time.sleep(3)
m.foto(S+"/20-energiemenue.ppm")
auf=len(re.findall(r"energie auf", lies()))
sag("  -> energie auf:", auf)
neu=[x for x in wins() if x not in vor]
sag("  -> neue Fenster:", neu[-2:] if neu else "keine")
if not neu: sag("ABBRUCH: Menue ging nicht auf"); p.kill(); sys.exit(1)
mx,my,mw,mh=(int(v) for v in neu[-1]); zh=mh//3
ziel = 1 if MODE=="neu" else 0
px,py = mx+mw//2, my+zh//2+ziel*zh
sag("Menue %d,%d %dx%d -> Punkt %d bei %d,%d" % (mx,my,mw,mh,ziel,px,py))
vor2=set(wins())
m.klick_auf(px,py); time.sleep(3)
m.foto(S+"/30-abfrage.ppm")
sag("  -> wahl:", re.findall(r"energie wahl=(\d+)", lies()))
sag("  -> frage:", re.findall(r"energie frage=(\d+)", lies()))
dlg=[x for x in wins() if x not in vor2]
sag("  -> Dialog:", dlg[-1] if dlg else "keiner")
if not dlg: sag("ABBRUCH: keine Rueckfrage"); p.kill(); sys.exit(1)
dx,dy,dw,dh=(int(v) for v in dlg[-1])
if MODE=="nein":
    sag("ABBRECHEN mit Flucht")
    m.taste("esc"); time.sleep(3)
    m.foto(S+"/40-abgebrochen.ppm")
    sag("  -> abbruch:", len(re.findall(r"energie abbruch", lies())))
    sag("  -> tat:", re.findall(r"energie tat (\d+)", lies()))
else:
    # Die TAT steht RECHTS. Mehrere Punkte der Knopfzeile probieren --
    # die genaue Knopfbreite rechnet wlib selbst aus dem Text.
    # SEIT DER FLUCHTTASTEN-KORREKTUR STEHT DIE TAT LINKS und der
    # Abbruch rechts (siehe launcher.fi, pw_frage_auf). Also von der
    # Mitte nach links suchen, nicht vom rechten Rand.
    ok=False
    for bx in (dx+dw-150, dx+dw-170, dx+dw-130, dx+dw-190, dx+dw-110):
        for by in (dy+dh-26, dy+dh-30, dy+dh-20):
            m.klick_auf(bx,by); time.sleep(2)
            if re.findall(r"energie tat (\d+)", lies()):
                sag("  TAT ausgeloest mit Klick auf %d,%d" % (bx,by)); ok=True; break
            if len(re.findall(r"energie abbruch", lies())):
                sag("  (Abbrechen getroffen bei %d,%d)" % (bx,by)); break
        if ok: break
    if not ok:
        sag("  Knopf nicht getroffen -- Tastatur: tab, tab, enter")
        m.taste("tab"); time.sleep(0.5); m.taste("ret"); time.sleep(2)
    sag("  -> tat:", re.findall(r"energie tat (\d+)", lies()))
    try:
        m.foto(S+"/40-danach.ppm")
    except Exception as e:
        sag("  kein Foto mehr (%s) -- die Maschine geht" % type(e).__name__)
# ------------------------------------------------------------- Urteil
sag("\n== warte auf das Ende der Maschine")
ende=None
for i in range(12):
    if p.poll() is not None: ende=p.returncode; break
    time.sleep(1)
t=lies()
sag("\n=== BEFUND (%s) ===" % MODE)
sag("QEMU beendet:", "ja, rc=%s" % ende if ende is not None else "NEIN, laeuft noch")
for pat,was in ((r"energie auf","Menue aufgeklappt"),
                (r"energie wahl=(\d+)","Punkt gewaehlt"),
                (r"energie frage=(\d+)","Rueckfrage"),
                (r"energie tat (\d+)","Tat"),
                (r"energie abbruch","Abbruch"),
                (r"energie selbst aus","Notweg ohne init"),
                (r"init: herunterfahren","init faehrt herunter"),
                (r"init: umounts=(\d+)","init hat ausgehaengt"),
                (r"power: acpi pm1a=([0-9a-fx]+)","ACPI S5"),
                (r"power: reset","ACPI Reset"),
                (r"mb: flags=","Kern hochgekommen")):
    r=re.findall(pat,t); sag("  %-24s %s" % (was, ("%dx %s"%(len(r),r[:3])) if r else "-"))
if p.poll() is None: p.kill()
for f in sorted(os.listdir(S)):
    if f.endswith(".ppm"):
        try:
            from PIL import Image
            Image.open(os.path.join(S,f)).save(os.path.join(S,f[:-4]+".png"))
            os.unlink(os.path.join(S,f))
        except Exception: pass
sag("Bilder:", S)
