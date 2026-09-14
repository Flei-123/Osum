#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""syncbeleg.py -- SCHREIBT `sync` WIRKLICH, BEVOR DER STROM WEGGEHT?

Der Lauf mit dem Startmenue bootet aus einem MODUL (`modfs`): die Wurzel
liegt im Arbeitsspeicher, `blk.flush` kehrt dort sofort zurueck
(kernel/blk.fi:720, `DISK_DEV != DEV_ATA`), und ein `sync` ist damit
nachweislich ein Nichts. Ein Beleg "sync lief" waere aus so einem Lauf
eine Behauptung.

ALSO MIT ECHTER PLATTE, und in zwei Laeufen:

  1. Eine Datei schreiben und ueber denselben Weg herunterfahren, den
     der Energieknopf nimmt (`/bin/shutdown`, also /run/svc.cmd bzw.
     der Notweg sync+SYS_REBOOT).
  2. DIESELBE Platte noch einmal starten und nachsehen, ob die Datei
     da ist.

Steht sie da, hat der Abschaltweg die Puffer wirklich geschrieben.
Die GEGENPROBE ist der Lauf ohne Abschaltung: die Maschine wird
abgewuergt (kill -9), und dann darf die Datei FEHLEN -- sonst misst
dieser Test die Platte und nicht das Herunterfahren.
"""
import os, re, shutil, subprocess, sys, time
HIER=os.path.dirname(os.path.abspath(__file__)); os.chdir(HIER)
REPO=os.path.dirname(HIER)
W="/tmp/syncbeleg"; shutil.rmtree(W, ignore_errors=True); os.makedirs(W)
LOG=open("/tmp/befund-sync.txt","w",buffering=1)
def sag(*a): print(*a); print(*a,file=LOG)
kvm=["-accel","kvm","-cpu","host"] if os.access("/dev/kvm",os.W_OK) else ["-accel","tcg"]

# Eine Platte aus dem FERTIGEN Wurzelabbild -- dieselben Programme.
MKFS=os.path.join(REPO,"tools","osum","mkfs.py")
BAU=os.environ.get("BAUDIR","/tmp/pwimg8")
def platte():
    """Eine EIGENE Platte fuer diesen Beleg: dieselben Programme aus
    demselben Bau, aber `/etc/ziel = konsole`. Nur dann startet init
    die ctrl-Shell, die `script=` liest -- im Ziel `grafik` steht
    absichtlich keine Konsole in der Tafel (siehe die Begruendung in
    tools/usbimg/build.sh)."""
    open(W+"/ziel","w").write("konsole\n")
    open(W+"/inittab","w").write("sh:konsole:ctrl:/bin/sh\n")
    args=["python3",MKFS,"build",W+"/disk.img","8192","--v3","--inodes=256",
          "/bin/"]
    for prog in ("sh","echo","cat","ls","shutdown","reboot","init","sync","svc"):
        f=os.path.join(BAU,prog+".elf")
        if os.path.exists(f): args.append("/bin/%s=%s"%(prog,f))
    args += ["/etc/","/etc/ziel=%s/ziel@644:0:0"%W,
             "/etc/inittab=%s/inittab@644:0:0"%W,"/run/","/tmp/","/var/","/var/log/"]
    r=subprocess.run(args,capture_output=True)
    if r.returncode: sag("   mkfs:",r.stdout.decode()[-300:]); sys.exit(1)
platte()

def lauf(name, script, limit=120, kill_hart=False):
    ser=W+"/%s.txt"%name
    q=["qemu-system-x86_64"]+kvm+["-m","512",
       "-kernel",os.path.join(HIER,"osum.mb"),
       "-append","osum nokbd nosched noproc nofs noring3 script=%s"%script,
       "-drive","file=%s/disk.img,format=raw,if=ide,index=0"%W,
       "-serial","file:"+ser,"-display","none","-no-reboot",
       "-device","isa-debug-exit,iobase=0xf4,iosize=0x04"]
    p=subprocess.Popen(q,stdout=subprocess.DEVNULL,stderr=subprocess.STDOUT)
    t0=time.time()
    while time.time()-t0<limit:
        if p.poll() is not None: break
        if kill_hart and os.path.exists(ser):
            s=open(ser,"rb").read().decode("utf-8","replace")
            if "GESCHRIEBEN" in s:
                time.sleep(0.3); p.kill(); sag("   (hart abgewuergt)"); break
        time.sleep(0.3)
    else:
        p.kill()
    p.wait()
    return p.returncode, open(ser,"rb").read().decode("utf-8","replace") if os.path.exists(ser) else ""

sag("== 1. schreiben und SAUBER herunterfahren (derselbe Weg wie der Knopf)")
rc,t = lauf("a1", "echo HALLO-ENERGIE > /beleg.txt;echo GESCHRIEBEN;shutdown", 90)
sag("   QEMU rc=%s  (0 = ACPI, 21 = Ausgang des Pruefstands)" % rc)
for pat in (r"GESCHRIEBEN", r"shutdown: [^\n]*", r"power: acpi[^\n]*", r"init: [^\n]*"):
    for m in re.finditer(pat,t): sag("   ", m.group(0).strip())

sag("\n== 2. dieselbe Platte noch einmal starten und nachsehen")
rc2,t2 = lauf("a2", "cat /beleg.txt")
da = "HALLO-ENERGIE" in t2
sag("   /beleg.txt nach dem Neustart:", "DA" if da else "FEHLT")
i=t2.find("HALLO-ENERGIE")
if i>=0: sag("   gelesen:", t2[i:i+20].split("\n")[0])

sag("\n== 3. GEGENPROBE: schreiben und die Maschine ABWUERGEN (kein sync)")
platte()
rc3,t3 = lauf("b1", "echo HALLO-HART > /beleg2.txt;echo GESCHRIEBEN;sleep 9",
              limit=60, kill_hart=True)
rc4,t4 = lauf("b2", "cat /beleg2.txt")
da2 = "HALLO-HART" in t4
sag("   /beleg2.txt nach dem Abwuergen:", "DA" if da2 else "FEHLT")

sag("\n=== URTEIL ===")
sag("  sauberes Herunterfahren -> Datei da:      %s" % ("JA" if da else "NEIN"))
sag("  hartes Abwuergen        -> Datei da:      %s" % ("JA" if da2 else "NEIN"))
if da and not da2:
    sag("  => sync WIRKT: nur der saubere Weg hat die Puffer geschrieben.")
elif da and da2:
    sag("  => beide Wege schreiben; dieser Aufbau puffert nicht lange genug,")
    sag("     um den Unterschied zu zeigen. Der saubere Weg verliert nichts.")
else:
    sag("  => der saubere Weg hat die Datei NICHT gerettet -- das waere ein Fehler.")
